# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReports::FileIssueJob, type: :job do
  include ActiveJob::TestHelper

  let(:payload) { ErrorReports::Capture.call(RuntimeError.new("boom")).merge("occurrences" => 1) }

  # `perform_now` leaves the job in the execution context, where the
  # subscriber's own-job guard would read it in a later example.
  after { ActiveSupport::ExecutionContext.clear }

  it "records every occurrence even with no GitHub configured" do
    allow(ErrorReports::GithubIssues).to receive(:configured?).and_return(false)

    expect {
      described_class.perform_now(payload)
      described_class.perform_now(payload.merge("occurrences" => 3))
    }.to change(ErrorReport, :count).by(1)

    expect(ErrorReport.last.occurrences).to eq(4)
    expect(a_request(:any, /api\.github\.com/)).not_to have_been_made
  end

  it "hands the row to GitHub when configured" do
    allow(ErrorReports::GithubIssues).to receive(:configured?).and_return(true)
    client = instance_double(ErrorReports::GithubIssues, sync: nil)
    allow(ErrorReports::GithubIssues).to receive(:new).and_return(client)

    described_class.perform_now(payload)

    expect(client).to have_received(:sync).with(an_instance_of(ErrorReport))
  end

  # A raise here would retry, and a retry would count the occurrence
  # again — and there is nothing left to report a reporter's failure to.
  # The row is already counted, so the retry that is safe is a sync.
  it "never raises when GitHub is down, and hands the sync to the job that can retry" do
    allow(ErrorReports::GithubIssues).to receive(:configured?).and_return(true)
    client = instance_double(ErrorReports::GithubIssues)
    allow(client).to receive(:sync).and_raise(Faraday::ConnectionFailed, "down")
    allow(ErrorReports::GithubIssues).to receive(:new).and_return(client)

    expect { described_class.perform_now(payload) }.not_to raise_error

    expect(ErrorReport.count).to eq(1)
    expect(ErrorReports::SyncIssueJob).to have_been_enqueued.with(ErrorReport.last.id)
  end

  it "never raises when even the record cannot be written" do
    allow(ErrorReport).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, "db down")

    expect { described_class.perform_now(payload) }.not_to raise_error
    expect(ErrorReports::SyncIssueJob).not_to have_been_enqueued
  end
end
