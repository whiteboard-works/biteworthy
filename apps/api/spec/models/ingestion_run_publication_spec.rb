require "rails_helper"

RSpec.describe IngestionRun, "#maybe_publish!", type: :model do
  let(:restaurant) { create(:restaurant, status: "draft") }
  let(:run)        { create(:ingestion_run, :staged, restaurant: restaurant) }

  def add_items(decisions)
    decisions.each do |d|
      create(:ingestion_item, ingestion_run: run, decision: d)
    end
  end

  it "publishes when ≥80% of decided items are accepted" do
    # 4 accepted + 1 rejected = 80% accepted of 5 decided. Threshold met.
    add_items(%w[accepted accepted accepted accepted rejected])

    expect(run.maybe_publish!).to be true

    run.reload
    expect(run.published?).to        be true
    expect(restaurant.reload.status).to eq("published")
  end

  it "does not publish when below the 80% threshold" do
    # 3 accepted + 2 rejected = 60% accepted. No publish.
    add_items(%w[accepted accepted accepted rejected rejected])

    expect(run.maybe_publish!).to be false

    run.reload
    expect(run.staged?).to be true
    expect(restaurant.reload.status).to eq("draft")
  end

  it "ignores pending items in the denominator" do
    # 4 accepted + 1 rejected (decided) + 6 pending (not counted yet).
    # 80% of decided = pass.
    add_items(%w[accepted accepted accepted accepted rejected pending pending pending pending pending pending])

    expect(run.maybe_publish!).to be true
    expect(run.reload.published?).to be true
  end

  it "is a no-op if the run hasn't reached :staged yet" do
    queued = create(:ingestion_run, status: "extracting", restaurant: restaurant)
    create(:ingestion_item, ingestion_run: queued, decision: "accepted")

    expect(queued.maybe_publish!).to be false
    expect(queued.reload.extracting?).to be true
  end

  it "is a no-op when there are zero decided items" do
    add_items(%w[pending pending pending])

    expect(run.maybe_publish!).to be false
    expect(run.reload.staged?).to be true
  end

  it "leaves restaurant alone if it's already published" do
    restaurant.update!(status: "published")
    add_items(%w[accepted accepted accepted accepted accepted])

    expect { run.maybe_publish! }
      .not_to change { restaurant.reload.updated_at }

    expect(run.reload.published?).to be true
  end
end
