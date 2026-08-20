# frozen_string_literal: true

require "rails_helper"

# These pin *intent*, not string equality for its own sake: the reason
# each sentence exists is that it names a different next move. A test
# that only asserted "some message came back" could not fail when a
# refactor collapsed "start a new chat" back into "try again in a
# moment", which is precisely the regression this class was written to
# prevent.
RSpec.describe Chat::UpstreamError do
  def api_error(status:, body: nil, headers: {})
    AnthropicClient::ApiError.new(status: status, body: body, response_headers: headers)
  end

  # The symbol the log line carries. Same judgement as the sentence, in
  # the words an operator greps for — so a spike in the logs and a spike
  # in complaints are the same spike.
  describe ".kind_for" do
    it "names each failure the sentence distinguishes" do
      expect(described_class.kind_for(api_error(status: 529, body: "overloaded"))).to eq(:overloaded)
      expect(described_class.kind_for(api_error(status: 429, body: "slow down"))).to eq(:rate_limited)
      expect(described_class.kind_for(api_error(status: 401, body: "nope"))).to eq(:misconfigured)
      expect(described_class.kind_for(Faraday::TimeoutError.new("expired"))).to eq(:timed_out)
      expect(described_class.kind_for(Faraday::ConnectionFailed.new("refused"))).to eq(:unreachable)
      expect(described_class.kind_for(AnthropicClient::Stream::IncompleteError.new("cut"))).to eq(:dropped)
    end

    # :unreachable and :unknown share the generic sentence, and that is
    # the point of keeping the kinds apart: the log can tell them apart
    # even though the reader does not need to.
    it "keeps kinds apart that the copy deliberately merges" do
      unreachable = Faraday::ConnectionFailed.new("refused")
      unknown     = api_error(status: 500, body: "boom")

      expect(described_class.message_for(unreachable)).to eq(described_class.message_for(unknown))
      expect(described_class.kind_for(unreachable)).not_to eq(described_class.kind_for(unknown))
    end
  end

  describe "failures the user can wait out" do
    it "names overload as capacity, so waiting is the right move" do
      expect(described_class.message_for(api_error(status: 529, body: "overloaded")))
        .to eq(described_class::OVERLOADED)
    end

    # The stream carries its own failures as SSE `error` events, which
    # `Stream#raise_stream_error` reports with status 200 — the type is
    # the only signal, and the chat is the only streaming caller, so
    # missing this shape means missing it for every real user.
    it "recognises an overload delivered mid-stream, where the status is 200" do
      error = api_error(status: 200, body: { "type" => "overloaded_error", "message" => "Overloaded" })

      expect(described_class.message_for(error)).to eq(described_class::OVERLOADED)
    end

    it "quotes upstream's own retry-after rather than guessing" do
      message = described_class.message_for(
        api_error(status: 429, body: "rate limited", headers: { "Retry-After" => "45" })
      )

      expect(message).to include("in about 45 seconds")
    end

    it "rounds a long wait up to minutes, because 300 seconds reads as no time at all" do
      message = described_class.message_for(
        api_error(status: 429, body: "rate limited", headers: { "retry-after" => "300" })
      )

      expect(message).to include("in about 5 minutes")
    end

    it "falls back to a vague wait when upstream did not say how long" do
      message = described_class.message_for(api_error(status: 429, body: "rate limited"))

      expect(message).to include("in a moment")
    end
  end

  describe "failures no amount of waiting fixes" do
    # The whole reason this class exists. Retrying a transcript that no
    # longer fits sends the same too-long transcript, so "try again in a
    # moment" is advice that cannot work.
    it "sends someone with an oversized transcript to a new chat" do
      error = api_error(
        status: 400,
        body: { "type" => "error",
                "error" => { "type" => "invalid_request_error",
                             "message" => "prompt is too long: 214000 tokens > 200000 maximum" } }
      )

      expect(described_class.message_for(error)).to eq(described_class::TOO_LONG)
    end

    # The streaming connection has no JSON response middleware, so its
    # error bodies arrive as raw strings. Same failure, same sentence.
    it "reads the same failure out of an unparsed string body" do
      error = api_error(
        status: 400,
        body: '{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long"}}'
      )

      expect(described_class.message_for(error)).to eq(described_class::TOO_LONG)
    end

    it "does not blame the user for a bad request that is ours" do
      error = api_error(status: 400, body: { "error" => { "message" => "messages: unexpected role" } })

      expect(described_class.message_for(error)).to eq(described_class::REJECTED)
    end

    # Telling someone to retry a missing API key wastes their time on a
    # problem only we can see.
    it "owns a misconfigured key instead of asking for a retry" do
      expect(described_class.message_for(api_error(status: 401, body: "authentication_error")))
        .to eq(described_class::MISCONFIGURED)
      expect(described_class.message_for(api_error(status: 403, body: "permission_error")))
        .to eq(described_class::MISCONFIGURED)
    end
  end

  describe "connection-level failures" do
    it "calls a timeout what it is" do
      expect(described_class.message_for(Faraday::TimeoutError.new("execution expired")))
        .to eq(described_class::TIMED_OUT)
    end

    it "tells someone whose stream was cut that the conversation survived" do
      expect(described_class.message_for(AnthropicClient::Stream::IncompleteError.new("no message_stop")))
        .to eq(described_class::DROPPED)
    end
  end

  # A wrong specific explanation is worse than a vague true one: telling
  # someone to abandon a conversation over a five-second blip costs them
  # the thing they came for.
  describe "shapes it does not recognise" do
    it "stays generic for an unfamiliar status" do
      expect(described_class.message_for(api_error(status: 500, body: "boom"))).to eq(described_class::GENERIC)
    end

    it "stays generic for a body it cannot parse" do
      expect(described_class.message_for(api_error(status: 502, body: "<html>bad gateway</html>")))
        .to eq(described_class::GENERIC)
    end

    it "stays generic for an error from outside this family" do
      expect(described_class.message_for(RuntimeError.new("something else"))).to eq(described_class::GENERIC)
    end
  end
end
