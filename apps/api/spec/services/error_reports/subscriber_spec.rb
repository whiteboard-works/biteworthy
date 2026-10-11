# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReports::Subscriber do
  include ActiveJob::TestHelper

  subject(:subscriber) { described_class.new }

  let(:error) { RuntimeError.new("boom #{SecureRandom.hex}") }

  def report(context: {})
    subscriber.report(error, handled: true, severity: :warning, context: context, source: "application")
  end

  it "queues the failure as a plain payload with its count" do
    expect { report(context: { conversation_id: "c1" }) }
      .to have_enqueued_job(ErrorReports::FileIssueJob)
      .with(hash_including("error_class" => "RuntimeError", "context" => { "conversation_id" => "c1" }, "occurrences" => 1))
  end

  # The one loop that would be fatal: the filing job fails, reports
  # itself, queues another filing job, which fails...
  it "never reports the filing job's own failures" do
    expect { report(context: { job: ErrorReports::FileIssueJob.new }) }
      .not_to have_enqueued_job(ErrorReports::FileIssueJob)
  end

  it "queues a burst of the same failure once, not once per occurrence" do
    expect { 5.times { report } }.to have_enqueued_job(ErrorReports::FileIssueJob).once
  end

  # It runs inside whatever just failed. A second exception here would
  # replace the honest error with one about the reporter.
  it "never raises" do
    allow(ErrorReports::Capture).to receive(:call).and_raise("capture broke")

    expect { report }.not_to raise_error
  end
end
