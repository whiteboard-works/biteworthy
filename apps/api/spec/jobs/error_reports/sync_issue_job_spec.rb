# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReports::SyncIssueJob, type: :job do
  let(:report) { ErrorReport.record!(ErrorReports::Capture.call(RuntimeError.new("boom"))) }

  before { allow(ErrorReports::GithubIssues).to receive(:configured?).and_return(true) }

  # `perform_now` leaves the job in the execution context, where the
  # subscriber's own-job guard would read it in a later example.
  after { ActiveSupport::ExecutionContext.clear }

  it "syncs a report with occurrences the issue has not heard about" do
    client = instance_double(ErrorReports::GithubIssues, sync: nil)
    allow(ErrorReports::GithubIssues).to receive(:new).and_return(client)

    described_class.perform_now(report.id)

    expect(client).to have_received(:sync).with(report)
  end

  it "does nothing when the issue is already current, or the row is gone" do
    report.update!(issue_occurrences: report.occurrences)
    allow(ErrorReports::GithubIssues).to receive(:new)

    described_class.perform_now(report.id)
    described_class.perform_now(SecureRandom.uuid)

    expect(ErrorReports::GithubIssues).not_to have_received(:new)
  end

  # This may be the only chance a lone recurrence gets, so a blip has to
  # reach Active Job's retry rather than a log line. Safe to retry: the
  # row already holds the count, and a sync records nothing.
  it "lets a GitHub failure through to the retry" do
    client = instance_double(ErrorReports::GithubIssues)
    allow(client).to receive(:sync).and_raise(Faraday::ConnectionFailed, "down")
    allow(ErrorReports::GithubIssues).to receive(:new).and_return(client)

    expect { described_class.perform_now(report.id) }.to have_enqueued_job(described_class).with(report.id)
  end
end
