# frozen_string_literal: true

require "rails_helper"

# One issue per failure, a count instead of a flood, and a closed issue
# that comes back is reopened — unless someone said wontfix.
RSpec.describe ErrorReports::GithubIssues do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  subject(:issues) { described_class.new(token: "ghp_test", repo: repo) }

  let(:repo)    { "whiteboard-works/ops" }
  let(:base)    { "https://api.github.com/repos/#{repo}/issues" }
  let(:json)    { { "Content-Type" => "application/json" } }
  let(:payload) do
    ErrorReports::Capture.call(RuntimeError.new("boom"), context: { conversation_id: "c1", component: "chat" })
  end

  # The private-repo check is remembered per process; each example
  # starts without that memory so the check is really made.
  before do
    described_class.verified_private.clear
    stub_repo(private: true)
  end

  # Performing a job in an example leaves it in the execution context,
  # where the subscriber's own-job guard would read it later on.
  after { ActiveSupport::ExecutionContext.clear }

  def stub_repo(private:)
    stub_request(:get, "https://api.github.com/repos/#{repo}")
      .to_return(status: 200, body: { private: private }.to_json, headers: json)
  end

  # WebMock's `with` wants either options or a block, never a nil block.
  def capturing(stub, capture)
    capture ? stub.with(&capture) : stub
  end

  def stub_create(number: 7, &capture)
    capturing(stub_request(:post, base), capture)
      .to_return(status: 201, body: { number: number }.to_json, headers: json)
  end

  def stub_issue(number: 7, state: "open", labels: [], status: 200)
    stub_request(:get, "#{base}/#{number}")
      .to_return(status: status, body: { number: number, state: state, labels: labels.map { |l| { name: l } } }.to_json,
                 headers: json)
  end

  def stub_comment(number: 7, &capture)
    capturing(stub_request(:post, "#{base}/#{number}/comments"), capture)
      .to_return(status: 201, body: "{}", headers: json)
  end

  def stub_reopen(number: 7)
    stub_request(:patch, "#{base}/#{number}").with(body: { state: "open" }.to_json)
                                             .to_return(status: 200, body: "{}", headers: json)
  end

  def record(with = payload) = ErrorReport.record!(with)

  it "opens one issue for a new failure, with the details in the body" do
    sent   = nil
    create = stub_create { |req| sent = JSON.parse(req.body) }

    issues.sync(record)

    expect(create).to have_been_requested.once
    expect(ErrorReport.last.issue_number).to eq(7)
    expect(ErrorReport.last.issue_opened_at).to be_present
    expect(sent["title"]).to eq("[chat] RuntimeError: boom")
    expect(sent["labels"]).to eq(%w[bug auto-reported])
    expect(sent["body"]).to include("`RuntimeError`", "`conversation_id`=`c1`", "wontfix")
  end

  # A public repo as the target would publish every backtrace. The
  # check is one request, remembered for the life of the process.
  it "refuses to file into a repo that is not private" do
    stub_repo(private: false)
    create = stub_create

    expect { issues.sync(record) }.to raise_error(described_class::NotPrivate)
    expect(create).not_to have_been_requested
  end

  it "checks the repo once, not once per issue" do
    stub_create
    issues.sync(record)
    issues.sync(record(ErrorReports::Capture.call(ArgumentError.new("other"))))

    expect(a_request(:get, "https://api.github.com/repos/#{repo}")).to have_been_made.once
  end

  # What a person typed can end up quoted in a parser's or a
  # constraint's message, or echoed unquoted in a Postgres row. The row
  # keeps it; the issue gets the shape.
  it "posts the message's shape, never the quoted or echoed values" do
    sent = nil
    stub_create { |req| sent = JSON.parse(req.body) }
    message = "ERROR: null value\nDETAIL: Failing row contains (Jane Doe, I am pregnant, hunter2).\n" \
              "Key (email)=(a@b.com) exists; said \"I am\nceliac\""

    issues.sync(record(ErrorReports::Capture.call(RuntimeError.new(message))))

    expect(sent["body"]).to include("DETAIL: Failing row contains (…).\nKey (…)=(…) exists; said <str>")
    expect(sent["body"]).not_to include("Jane", "pregnant", "hunter2", "a@b.com", "celiac")
    expect(sent["title"]).not_to include("Jane", "pregnant")
  end

  it "fences a message that contains a code fence, so it cannot render as Markdown" do
    sent = nil
    stub_create { |req| sent = JSON.parse(req.body) }

    issues.sync(record(ErrorReports::Capture.call(RuntimeError.new("bad ```\n@everyone #1 ```"), context: { k: "a`b" })))

    expect(sent["body"]).to include("````\nbad ```\n@everyone #1 ```\n````")
    expect(sent["body"]).to include("`k`=`ab`")
  end

  it "counts a repeat within the hour without touching GitHub, and books one catch-up for when the hour ends" do
    stub_create
    issues.sync(record)

    expect {
      issues.sync(record)
      issues.sync(record)
    }.to have_enqueued_job(ErrorReports::SyncIssueJob).once.with(ErrorReport.last.id)

    expect(a_request(:get, /#{base}/)).not_to have_been_made
    expect(ErrorReport.last.occurrences).to eq(3)
    expect(ErrorReport.last.issue_occurrences).to eq(1)
  end

  it "adds one comment with the count once the hour is up" do
    stub_create
    issues.sync(record)
    record

    travel 61.minutes do
      sent = nil
      stub_issue
      comment = stub_comment { |req| sent = JSON.parse(req.body) }

      issues.sync(record)

      expect(comment).to have_been_requested.once
      expect(sent["body"]).to start_with("Still happening. 2 more since the last note (3 in all)")
      expect(ErrorReport.last.issue_occurrences).to eq(3)
    end
  end

  # The point of the whole thing: a fix that did not take should not be
  # able to hide behind a closed issue.
  it "reopens a closed issue that fires again" do
    stub_create
    issues.sync(record)

    travel 61.minutes do
      stub_issue(state: "closed")
      reopen = stub_reopen
      sent   = nil
      stub_comment { |req| sent = JSON.parse(req.body) }

      issues.sync(record)

      expect(reopen).to have_been_requested.once
      expect(sent["body"]).to start_with("Reopened: this came back after the issue was closed.")
    end
  end

  # The recurrence lands ten minutes after the close, inside the slot,
  # and is the only one for hours. The catch-up is what reopens it.
  it "reopens through the catch-up when the recurrence lands inside the hour" do
    allow(described_class).to receive_messages(configured?: true, new: issues)
    stub_create
    issues.sync(record)
    issues.sync(record)
    stub_issue(state: "closed")
    stub_reopen
    stub_comment

    travel 61.minutes do
      perform_enqueued_jobs(only: ErrorReports::SyncIssueJob)
    end

    expect(a_request(:patch, "#{base}/7")).to have_been_made.once
    expect(ErrorReport.last.issue_occurrences).to eq(2)
  end

  it "leaves a wontfix issue alone, counting only" do
    stub_create
    issues.sync(record)

    travel 61.minutes do
      stub_issue(state: "closed", labels: %w[wontfix])

      issues.sync(record)

      expect(a_request(:patch, /#{repo}/)).not_to have_been_made
      expect(a_request(:post, %r{/comments})).not_to have_been_made
      expect(ErrorReport.last.occurrences).to eq(2)
    end
  end

  it "opens a replacement when the tracked issue is gone" do
    stub_create
    issues.sync(record)

    travel 61.minutes do
      stub_issue(status: 404)
      stub_create(number: 9)

      issues.sync(record)

      # Two creates in all: the original, and the replacement.
      expect(a_request(:post, base)).to have_been_made.twice
      expect(ErrorReport.last.issue_number).to eq(9)
    end
  end

  # A refused request must not cost an hour of silence: the first
  # occurrence of a one-off crash would otherwise never be filed at all.
  it "gives the slot back when GitHub refuses, so the next occurrence tries again" do
    stub_request(:post, base).to_return(status: 503, body: "{}", headers: json)
    expect { issues.sync(record) }.to raise_error(described_class::RequestFailed, /503/)

    stub_create
    issues.sync(record)

    # The refused attempt and the one that got through.
    expect(a_request(:post, base)).to have_been_made.twice
    expect(ErrorReport.last.issue_number).to eq(7)
  end

  it "stops opening new issues past the hourly cap, and keeps counting" do
    stub_create
    stub_const("#{described_class}::OPEN_LIMIT_PER_HOUR", 1)
    issues.sync(record)

    other = ErrorReports::Capture.call(ArgumentError.new("another"))
    expect {
      issues.sync(record(other))
      issues.sync(record(other))
    }.to have_enqueued_job(ErrorReports::SyncIssueJob).once

    expect(a_request(:post, base)).to have_been_made.once
    expect(ErrorReport.find_by(fingerprint: other["fingerprint"]).occurrences).to eq(2)
  end

  describe ".configured?" do
    it "needs both the token and a private repo to post to" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GITHUB_ERROR_REPORTS_TOKEN").and_return("ghp_x")
      allow(ENV).to receive(:[]).with("GITHUB_ERROR_REPORTS_REPO").and_return(nil)

      expect(described_class.configured?).to be(false)

      allow(ENV).to receive(:[]).with("GITHUB_ERROR_REPORTS_REPO").and_return("whiteboard-works/ops")

      expect(described_class.configured?).to be(true)
    end
  end
end
