require "rails_helper"

# An upload that was never scanned is invisible to everything else in the
# app — no record references it, so nothing else would ever delete it.
#
# The dangerous direction here is deleting too much: these are people's
# menu photos, and a blob attached to a real scan must never be swept.
RSpec.describe PurgeUnscannedAttachmentsJob do
  # The job enqueues purges rather than performing them, so a slow storage
  # backend cannot stall the sweep. Draining them here is what makes these
  # assert on the blob actually being gone.
  include ActiveJob::TestHelper

  def blob(created_at:, filename: "menu.jpg")
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("bytes"), filename: filename, content_type: "image/jpeg"
    ).tap { |b| b.update_column(:created_at, created_at) }
  end

  it "purges an upload nobody ever scanned" do
    orphan = blob(created_at: 3.days.ago)

    expect { perform_enqueued_jobs { described_class.perform_now } }
      .to change { ActiveStorage::Blob.exists?(orphan.id) }.from(true).to(false)
  end

  # The age floor is the whole safety story: an upload seconds old is
  # almost certainly mid-flight, with the person still typing the message
  # that will reference it.
  it "leaves a fresh upload alone" do
    fresh = blob(created_at: 5.minutes.ago)

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActiveStorage::Blob.exists?(fresh.id)).to be(true)
  end

  # The one that matters. A scanned upload is attached to its run, and
  # sweeping it would destroy the input of a real menu scan.
  it "never touches a blob attached to a scan, however old" do
    run      = create(:ingestion_run)
    attached = blob(created_at: 1.year.ago)
    run.inputs.attach(attached)

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActiveStorage::Blob.exists?(attached.id)).to be(true)
  end

  # A backlog drains over successive runs rather than flooding the queue.
  it "bounds how many it enqueues in one pass" do
    stub_const("#{described_class}::MAX_PER_RUN", 2)
    3.times { blob(created_at: 3.days.ago) }

    expect(described_class.perform_now).to eq(2)
  end

  it "reports nothing to do without raising" do
    expect(described_class.perform_now).to eq(0)
  end
end
