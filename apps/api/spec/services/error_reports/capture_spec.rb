# frozen_string_literal: true

require "rails_helper"

# The fingerprint is the whole product: it decides whether a failure is
# a new issue or a count on an old one. These pin what it must ignore (a
# record id, a line number, a quoted value) and what it must not (the
# class, the shape of the message).
RSpec.describe ErrorReports::Capture do
  # A backtrace the way production sees one: our frame under Rails.root,
  # then the gems. Raising inside the spec would not do — the backtrace
  # cleaner keeps `app/`, `lib/`, and `config/` and silences `spec/`, so
  # a spec-raised error arrives with no app frames at all.
  def failing(message, klass: RuntimeError, line: 152)
    klass.new(message).tap do |error|
      error.set_backtrace([
        "#{Rails.root}/app/services/chat/agent_loop.rb:#{line}:in 'run'",
        "#{Rails.root}/app/jobs/chat/completion_job.rb:40:in 'execute'",
        "/gems/activejob-8.1.4/lib/active_job/execution.rb:66:in 'perform_now'"
      ])
    end
  end

  describe "fingerprint" do
    it "is the same for the same failure on different records" do
      a = described_class.call(failing("Couldn't find Conversation with 'id'=#{SecureRandom.uuid}"))
      b = described_class.call(failing("Couldn't find Conversation with 'id'=#{SecureRandom.uuid}"))

      expect(a["fingerprint"]).to eq(b["fingerprint"])
    end

    it "ignores the frame's line number, so a deploy does not open a second issue" do
      expect(described_class.call(failing("boom", line: 152))["fingerprint"])
        .to eq(described_class.call(failing("boom", line: 153))["fingerprint"])
    end

    it "folds measurements, decimals, and long numbers, which change on every occurrence" do
      a = described_class.call(failing("Timeout after 15.003s, took 5231ms, at 1696950000"))
      b = described_class.call(failing("Timeout after 16.9s, took 48ms, at 1696950001"))

      expect(a["fingerprint"]).to eq(b["fingerprint"])
    end

    it "keeps short numbers, so a 529 and a 401 are different problems" do
      overloaded   = described_class.call(failing("Anthropic API returned 529: overloaded"))
      unauthorized = described_class.call(failing("Anthropic API returned 401: unauthorized"))

      expect(overloaded["fingerprint"]).not_to eq(unauthorized["fingerprint"])
    end

    it "separates error classes that share a message" do
      expect(described_class.call(failing("boom"))["fingerprint"])
        .not_to eq(described_class.call(failing("boom", klass: ArgumentError))["fingerprint"])
    end

    it "separates the same error raised from different places" do
      elsewhere = failing("boom")
      elsewhere.set_backtrace([ "#{Rails.root}/app/services/chat/titler.rb:10:in 'call'" ])

      expect(described_class.call(failing("boom"))["fingerprint"])
        .not_to eq(described_class.call(elsewhere)["fingerprint"])
    end
  end

  # What is stored. A parser or a constraint quotes whatever it choked
  # on, and that can be a person's words or address; a row that belongs
  # to no account must never hold them.
  describe ".normalized" do
    it "blanks ids, emails, quoted text, and anything in parentheses, nested or not" do
      shape = described_class.normalized(
        %(Key (email)=(a@b.com) exists; user #{SecureRandom.uuid} said "I am\npregnant" at 0x7f3a; row ((Jane), hunter2))
      )

      expect(shape).to eq("Key (…)=(…) exists; user <id> said <str> at <addr>; row (…)")
    end
  end

  describe "title" do
    it "leads with where, then what, then the first line of why, with the variable parts blanked" do
      payload = described_class.call(failing("Overloaded for 'celiac tacos'\nsecond line"), context: { component: "chat" })

      expect(payload["title"]).to eq("[chat] RuntimeError: Overloaded for <str>")
    end

    it "falls back to the job's name when there is no component" do
      payload = described_class.call(failing("boom"), context: { job: ExtractMenuJob.new })

      expect(payload["title"]).to eq("[ExtractMenuJob] RuntimeError: boom")
    end
  end

  describe "context" do
    it "keeps scalars and names the job and controller instead of serializing them" do
      controller = Api::V1::ConversationTurnsController.new
      allow(controller).to receive(:action_name).and_return("stream")
      payload = described_class.call(
        failing("boom"),
        context: { conversation_id: "c1", rounds: 3, job: ExtractMenuJob.new, controller: controller, run: Object.new }
      )

      expect(payload["context"]).to eq(
        "conversation_id" => "c1", "rounds" => 3,
        "job" => "ExtractMenuJob", "controller" => "Api::V1::ConversationTurnsController#stream"
      )
    end

    it "hides what the log filter hides" do
      payload = described_class.call(failing("boom"), context: { api_key: "sk-ant-real", path: "/x" })

      expect(payload["context"]).to eq("api_key" => "[FILTERED]", "path" => "/x")
    end
  end

  it "stores the message's shape, not the message" do
    payload = described_class.call(failing(%(Failing row contains (Jane Doe, pregnant). Said "I am celiac" to a@b.com)))

    expect(payload["message"]).to eq("Failing row contains (…). Said <str> to <email>")
  end

  # The same scrubber as the PostHog path, so a credential shape that is
  # kept out of one place is kept out of both.
  it "redacts credentials quoted in the message" do
    payload = described_class.call(failing(
      "401 for sk-ant-api03-abcdef; ghp_12345; re_abcdefghijklmnopqrstuvwxyz; " \
      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig and postgres://neon:hunter2@host/db"
    ))

    expect(payload["message"]).to eq(
      "401 for sk-ant-<redacted> ghp_<redacted> re_<redacted>; <jwt> and postgres://<redacted>@host/db"
    )
  end

  # A verify or reset link and a signed blob path are bearer credentials
  # that no key-prefix pattern recognizes.
  it "blanks query-string values and signed Active Storage paths" do
    payload = described_class.call(failing(
      "Net::ReadTimeout fetching https://api.bite-worthy.com/verify?t=abc123xyz&profile=celiac " \
      "then /rails/active_storage/blobs/redirect/abc--def/menu.pdf from 203.0.113.9"
    ), context: { url: "https://api.bite-worthy.com/reset?token=secret" })

    expect(payload["message"]).to eq(
      "Net::ReadTimeout fetching https://api.bite-worthy.com/verify?t=<q>&profile=<q> " \
      "then /rails/active_storage/<redacted> from <ip>"
    )
    expect(payload["context"]).to eq("url" => "https://api.bite-worthy.com/reset?token=<q>")
  end

  it "bounds the message" do
    payload = described_class.call(failing("x" * 5_000))

    expect(payload["message"].length).to be <= described_class::MESSAGE_CHARS
  end

  it "keeps the app's frames, relative to the root, and drops the gems'" do
    payload = described_class.call(failing("boom"))

    expect(payload["backtrace"]).to eq(
      "app/services/chat/agent_loop.rb:152:in 'run'\napp/jobs/chat/completion_job.rb:40:in 'execute'"
    )
  end

  it "survives an error with no backtrace at all" do
    payload = described_class.call(RuntimeError.new("never raised"))

    expect(payload["backtrace"]).to be_nil
    expect(payload["fingerprint"]).to be_present
  end
end
