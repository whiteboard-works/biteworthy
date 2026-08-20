# frozen_string_literal: true

require "rails_helper"

# The streaming path is retried, and the thing that makes that safe is
# not which error came back — it is whether the caller has already been
# handed a fragment. These pin that gate from both sides, because the
# failure mode of getting it wrong is a user reading the same answer
# twice with nothing to say which one is real.
RSpec.describe AnthropicClient, "streamed retries" do
  let(:base_url) { "https://api.anthropic.test" }
  let(:client)   { described_class.new(api_key: "sk-ant-test-key", base_url: base_url) }

  # Nothing here is waiting on real backoff.
  before { stub_const("AnthropicClient::STREAM_RETRY_BASE_INTERVAL", 0) }

  def sse(*events)
    events.map { |e| "event: #{e['type']}\ndata: #{e.to_json}\n\n" }.join
  end

  def good_stream(text: "hello")
    sse(
      { "type" => "message_start",
        "message" => { "id" => "msg_1", "role" => "assistant", "content" => [],
                       "usage" => { "input_tokens" => 10 } } },
      { "type" => "content_block_start", "index" => 0,
        "content_block" => { "type" => "text", "text" => "" } },
      { "type" => "content_block_delta", "index" => 0,
        "delta" => { "type" => "text_delta", "text" => text } },
      { "type" => "message_delta", "delta" => { "stop_reason" => "end_turn" },
        "usage" => { "output_tokens" => 5 } },
      { "type" => "message_stop" }
    )
  end

  # A stream that says something and then dies without `message_stop`.
  def truncated_stream(text: "half an ans")
    sse(
      { "type" => "message_start",
        "message" => { "id" => "msg_1", "role" => "assistant", "content" => [],
                       "usage" => { "input_tokens" => 10 } } },
      { "type" => "content_block_start", "index" => 0,
        "content_block" => { "type" => "text", "text" => "" } },
      { "type" => "content_block_delta", "index" => 0,
        "delta" => { "type" => "text_delta", "text" => text } }
    )
  end

  def stream!(&on_delta)
    client.messages_stream(system: [], messages: [ { role: "user", content: "x" } ], &on_delta)
  end

  describe "before the reader has seen anything" do
    it "retries an overload that arrives as the response status" do
      stub = stub_request(:post, "#{base_url}/v1/messages")
             .to_return({ status: 529, body: '{"type":"error","error":{"type":"overloaded_error"}}' },
                        { status: 200, body: good_stream, headers: { "Content-Type" => "text/event-stream" } })

      seen = []
      message = stream! { |_kind, text| seen << text }

      expect(message["stop_reason"]).to eq("end_turn")
      # The answer arrives exactly once — the abandoned attempt streamed
      # nothing, so there is nothing to double up.
      expect(seen.join).to eq("hello")
      expect(stub).to have_been_requested.twice
    end

    # Overload inside a stream is delivered as an SSE `error` event with
    # a 200 status, so a retry policy keyed on status alone would miss
    # the most common transient failure there is.
    it "retries an overload delivered as an SSE error event" do
      overloaded = sse({ "type" => "error",
                         "error" => { "type" => "overloaded_error", "message" => "Overloaded" } })
      stub = stub_request(:post, "#{base_url}/v1/messages")
             .to_return({ status: 200, body: overloaded, headers: { "Content-Type" => "text/event-stream" } },
                        { status: 200, body: good_stream, headers: { "Content-Type" => "text/event-stream" } })

      expect(stream!["stop_reason"]).to eq("end_turn")
      expect(stub).to have_been_requested.twice
    end

    it "retries a connection that died before it said anything" do
      stub = stub_request(:post, "#{base_url}/v1/messages")
             .to_return({ status: 200, body: "", headers: { "Content-Type" => "text/event-stream" } },
                        { status: 200, body: good_stream, headers: { "Content-Type" => "text/event-stream" } })

      expect(stream!["stop_reason"]).to eq("end_turn")
      expect(stub).to have_been_requested.twice
    end

    it "gives up after the third attempt rather than retrying forever" do
      stub = stub_request(:post, "#{base_url}/v1/messages").to_return(status: 529, body: "overloaded")

      expect { stream! }.to raise_error(AnthropicClient::ApiError) { |e| expect(e.status).to eq(529) }
      expect(stub).to have_been_requested.times(described_class::STREAM_MAX_ATTEMPTS)
    end
  end

  # The property the old "not retried, full stop" comment was protecting,
  # and the reason the gate is the latch rather than the error class.
  describe "once the reader has seen something" do
    it "does not retry a stream that failed mid-answer" do
      stub = stub_request(:post, "#{base_url}/v1/messages")
             .to_return(status: 200, body: truncated_stream,
                        headers: { "Content-Type" => "text/event-stream" })

      seen = []
      expect { stream! { |_kind, text| seen << text } }
        .to raise_error(AnthropicClient::Stream::IncompleteError)

      expect(seen.join).to eq("half an ans")
      # The same failure with nothing emitted is retried — see above. The
      # only difference here is that a person already read it.
      expect(stub).to have_been_requested.once
    end
  end

  describe "failures a second attempt cannot help" do
    it "does not retry a 400" do
      stub = stub_request(:post, "#{base_url}/v1/messages")
             .to_return(status: 400, body: '{"type":"error","error":{"type":"invalid_request_error"}}')

      expect { stream! }.to raise_error(AnthropicClient::ApiError)
      expect(stub).to have_been_requested.once
    end

    it "does not retry a 401" do
      stub = stub_request(:post, "#{base_url}/v1/messages").to_return(status: 401, body: "nope")

      expect { stream! }.to raise_error(AnthropicClient::ApiError)
      expect(stub).to have_been_requested.once
    end

    # A read timeout has already spent the full read budget getting
    # nowhere; spending it again pushes the turn past the loop's deadline
    # to reach the same answer.
    it "does not retry a read timeout" do
      stub = stub_request(:post, "#{base_url}/v1/messages").to_raise(Faraday::TimeoutError)

      expect { stream! }.to raise_error(Faraday::TimeoutError)
      expect(stub).to have_been_requested.once
    end
  end

  # Anthropic bills an attempt that died halfway as readily as one that
  # finished, and the conversation spend ceiling is enforced off
  # `last_usage`. A retry that dropped the abandoned attempt's tokens
  # would quietly widen a ceiling the loop documents as overshooting "by
  # at most one round's cost".
  describe "what a retry costs" do
    it "carries the abandoned attempt's tokens into the usage it reports" do
      # Dies after message_start, so it really did read the prompt.
      partial = sse(
        { "type" => "message_start",
          "message" => { "id" => "msg_0", "role" => "assistant", "content" => [],
                         "usage" => { "input_tokens" => 900, "cache_read_input_tokens" => 40 } } },
        { "type" => "error", "error" => { "type" => "overloaded_error" } }
      )
      stub_request(:post, "#{base_url}/v1/messages")
        .to_return({ status: 200, body: partial, headers: { "Content-Type" => "text/event-stream" } },
                   { status: 200, body: good_stream, headers: { "Content-Type" => "text/event-stream" } })

      client.messages_stream(system: [], messages: [ { role: "user", content: "x" } ]) { |_k, _t| nil }

      # 10 from the successful attempt + 900 from the one thrown away.
      expect(client.last_usage["input_tokens"]).to eq(910)
      expect(client.last_usage["cache_read_input_tokens"]).to eq(40)
      expect(client.last_usage["output_tokens"]).to eq(5)
    end

    it "reports only the real call when nothing was retried" do
      stub_request(:post, "#{base_url}/v1/messages")
        .to_return(status: 200, body: good_stream, headers: { "Content-Type" => "text/event-stream" })

      stream!
      expect(client.last_usage["input_tokens"]).to eq(10)
    end
  end

  describe "what it records for debugging" do
    it "keeps upstream's request id off the successful response" do
      stub_request(:post, "#{base_url}/v1/messages")
        .to_return(status: 200, body: good_stream,
                   headers: { "Content-Type" => "text/event-stream", "request-id" => "req_abc123" })

      stream!
      expect(client.last_request_id).to eq("req_abc123")
    end
  end
end
