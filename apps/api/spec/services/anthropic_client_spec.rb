require "rails_helper"

RSpec.describe AnthropicClient do
  let(:api_key)    { "sk-ant-test-key" }
  let(:base_url)   { "https://api.anthropic.test" }
  let(:client)     { described_class.new(api_key: api_key, base_url: base_url) }

  describe "#system_blocks" do
    it "wraps text into Anthropic content blocks" do
      blocks = client.system_blocks({ text: "Hello" }, { text: "World" })

      expect(blocks).to eq([
        { type: "text", text: "Hello" },
        { type: "text", text: "World" }
      ])
    end

    it "marks cache: true blocks with ephemeral cache_control" do
      blocks = client.system_blocks(
        { text: "uncached preamble" },
        { text: "huge taxonomy", cache: true }
      )

      expect(blocks.last).to include(
        type: "text",
        text: "huge taxonomy",
        cache_control: { type: "ephemeral" }
      )
      expect(blocks.first).not_to have_key(:cache_control)
    end
  end

  describe "#image_block" do
    it "base64-encodes an ActiveStorage::Blob-shaped object" do
      blob = double("Blob", download: "binary-image-bytes", content_type: "image/png")

      block = client.image_block(blob)

      expect(block).to include(
        type: "image",
        source: include(
          type: "base64",
          media_type: "image/png",
          data: Base64.strict_encode64("binary-image-bytes")
        )
      )
    end

    it "accepts a raw IO and defaults media_type to image/jpeg" do
      io = StringIO.new("jpg-bytes")

      block = client.image_block(io)

      expect(block[:source][:media_type]).to eq("image/jpeg")
      expect(block[:source][:data]).to        eq(Base64.strict_encode64("jpg-bytes"))
    end

    it "honors an explicit media_type override" do
      block = client.image_block(StringIO.new("p"), media_type: "image/webp")
      expect(block[:source][:media_type]).to eq("image/webp")
    end
  end

  describe "#messages_create" do
    let(:happy_response_body) do
      {
        id:    "msg_01abc",
        model: "claude-sonnet-4-6",
        role:  "assistant",
        content: [
          { type: "text", text: '{"sections":[{"name":"Tacos","items":[]}]}' }
        ],
        usage: { input_tokens: 10, output_tokens: 5,
                 cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }
      }.to_json
    end

    it "POSTs to /v1/messages with auth + version headers and the right body" do
      stub = stub_request(:post, "#{base_url}/v1/messages")
        .with(
          headers: {
            "X-Api-Key"         => api_key,
            "Anthropic-Version" => described_class::ANTHROPIC_VERSION,
            "Content-Type"      => "application/json"
          },
          body: hash_including(
            "model"      => described_class::DEFAULT_MODEL,
            "max_tokens" => described_class::DEFAULT_MAX_TOKENS
          )
        )
        .to_return(status: 200, body: happy_response_body,
                   headers: { "Content-Type" => "application/json" })

      result = client.messages_create(
        system:   client.system_blocks({ text: "you are a menu OCR" }),
        messages: [{ role: "user", content: [{ type: "text", text: "extract" }] }]
      )

      expect(stub).to have_been_requested
      expect(result["id"]).to eq("msg_01abc")
    end

    it "returns the parsed payload on a 200 (no schema given)" do
      stub_request(:post, "#{base_url}/v1/messages")
        .to_return(status: 200, body: happy_response_body,
                   headers: { "Content-Type" => "application/json" })

      result = client.messages_create(
        system:   [{ type: "text", text: "x" }],
        messages: [{ role: "user", content: "hello" }]
      )

      expect(result["content"].first["text"]).to include("Tacos")
    end

    it "exposes the response usage via #last_usage (Phase 6.1.1 cost accrual)" do
      stub_request(:post, "#{base_url}/v1/messages")
        .to_return(status: 200, body: happy_response_body,
                   headers: { "Content-Type" => "application/json" })

      expect(client.last_usage).to be_nil

      client.messages_create(
        system:   [{ type: "text", text: "x" }],
        messages: [{ role: "user", content: "hello" }]
      )

      expect(client.last_usage).to eq(
        "input_tokens" => 10, "output_tokens" => 5,
        "cache_creation_input_tokens" => 0, "cache_read_input_tokens" => 0
      )
    end

    context "with response_schema" do
      let(:menu_schema) do
        {
          type: "object",
          required: ["sections"],
          properties: {
            sections: {
              type: "array",
              items: {
                type: "object",
                required: ["name", "items"],
                properties: { name: { type: "string" }, items: { type: "array" } }
              }
            }
          }
        }
      end

      it "validates + returns the parsed JSON when the model returns valid output" do
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: happy_response_body,
                     headers: { "Content-Type" => "application/json" })

        result = client.messages_create(
          system: [{ type: "text", text: "x" }],
          messages: [{ role: "user", content: "y" }],
          response_schema: menu_schema
        )

        expect(result).to include("sections")
        expect(result["sections"].first["name"]).to eq("Tacos")
      end

      it "raises ValidationError when the response doesn't satisfy the schema" do
        bad_body = {
          id: "msg_x", model: "x", role: "assistant",
          content: [{ type: "text", text: '{"wrong_key": []}' }]
        }.to_json
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: bad_body,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(
            system: [{ type: "text", text: "x" }],
            messages: [{ role: "user", content: "y" }],
            response_schema: menu_schema
          )
        }.to raise_error(AnthropicClient::ValidationError) { |error|
          expect(error.errors).not_to be_empty
        }
      end

      # A response cut off at the output limit is *also* unparseable
      # JSON, so whichever check runs first names the failure — and
      # "the model wrote malformed JSON" is the wrong name for "the
      # model was cut off". It sent us looking at the prompt for months
      # while the fix was the budget. This is the production shape: the
      # 2026-08-09 run billed 16¢ on 10,147 input tokens, which is only
      # reachable with output at exactly the 8,000-token cap.
      it "raises TruncatedError, not ValidationError, when the model was cut off" do
        cut_off = {
          id: "msg_x", model: "x", role: "assistant",
          stop_reason: "max_tokens",
          content: [{ type: "text", text: '{"sections": [{"name": "Tac' }]
        }.to_json
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: cut_off,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(
            system: [{ type: "text", text: "x" }],
            messages: [{ role: "user", content: "y" }],
            max_tokens: 16_000,
            response_schema: menu_schema
          )
        }.to raise_error(AnthropicClient::TruncatedError) { |error|
          expect(error.max_tokens).to eq(16_000)
          expect(error.message).to include("incomplete")
        }
      end

      # Every non-streaming caller, not only the schema'd ones. A
      # schema-less caller that got a half-finished answer with no signal
      # is the quieter version of the same bug.
      it "raises TruncatedError even when no schema was asked for" do
        cut_off = {
          id: "msg_x", model: "x", role: "assistant",
          stop_reason: "max_tokens",
          content: [{ type: "text", text: "Half a sentence that stops" }]
        }.to_json
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: cut_off,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(
            system: [{ type: "text", text: "x" }],
            messages: [{ role: "user", content: "y" }]
          )
        }.to raise_error(AnthropicClient::TruncatedError)
      end

      # Only when it was actually cut off. A `max_tokens` stop on a
      # response that happens to be complete JSON is still a truncation —
      # but an `end_turn` that fails to parse is not, and must keep
      # reporting as the schema failure it is.
      it "still raises ValidationError for malformed output that finished" do
        malformed = {
          id: "msg_x", model: "x", role: "assistant",
          stop_reason: "end_turn",
          content: [{ type: "text", text: '{"sections": [{"name" >5600}]}' }]
        }.to_json
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: malformed,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(
            system: [{ type: "text", text: "x" }],
            messages: [{ role: "user", content: "y" }],
            response_schema: menu_schema
          )
        }.to raise_error(AnthropicClient::ValidationError)
      end

      it "raises ValidationError when the response text isn't JSON at all" do
        prose_body = {
          id: "msg_x", model: "x", role: "assistant",
          content: [{ type: "text", text: "Sorry, I can't help with that." }]
        }.to_json
        stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 200, body: prose_body,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(
            system: [{ type: "text", text: "x" }],
            messages: [{ role: "user", content: "y" }],
            response_schema: menu_schema
          )
        }.to raise_error(AnthropicClient::ValidationError, /JSON parse failed/)
      end
    end

    context "error handling" do
      it "raises ApiError on a 401 (and does not retry)" do
        stub = stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 401, body: { error: "invalid api key" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        expect {
          client.messages_create(system: [], messages: [{ role: "user", content: "x" }])
        }.to raise_error(AnthropicClient::ApiError) { |error|
          expect(error.status).to eq(401)
        }

        expect(stub).to have_been_requested.once
      end

      it "retries 429 then raises if it stays bad" do
        stub = stub_request(:post, "#{base_url}/v1/messages")
          .to_return(status: 429, body: "rate limited")

        expect {
          client.messages_create(system: [], messages: [{ role: "user", content: "x" }])
        }.to raise_error(AnthropicClient::ApiError)

        # faraday-retry default is up to (1 + max=3) = 4 attempts
        expect(stub).to have_been_requested.at_least_times(2)
      end
    end
  end
end
