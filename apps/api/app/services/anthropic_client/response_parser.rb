# frozen_string_literal: true

require "json"
require "json-schema"

# Pulls the first text content block out of an Anthropic /v1/messages
# response and validates it against a JSON Schema.
#
# Anthropic responses look like:
#   {
#     "id": "msg_...",
#     "content": [
#       { "type": "text", "text": "{\"sections\": [...]}" }
#     ],
#     ...
#   }
#
# We grab the first text block, parse it as JSON, and validate against
# the schema. The Anthropic system prompt is responsible for telling
# the model "respond with strict JSON, no prose" — JSON Schema
# validation catches the cases where it doesn't comply.
class AnthropicClient::ResponseParser
  class << self
    def first_text(parsed_response)
      content = parsed_response.is_a?(Hash) ? (parsed_response["content"] || parsed_response[:content]) : nil
      block   = content&.find { |b| (b["type"] || b[:type]) == "text" }
      block&.fetch("text") { block[:text] } || ""
    end

    # Returns the parsed response data on success; raises
    # AnthropicClient::ValidationError on either JSON parse failure
    # or schema mismatch.
    def parse_and_validate(text, schema)
      payload = JSON.parse(text)
    rescue JSON::ParserError => e
      raise AnthropicClient::ValidationError.new(
        raw_body: text, errors: ["JSON parse failed: #{e.message}"]
      )
    else
      errors = JSON::Validator.fully_validate(schema, payload)
      raise AnthropicClient::ValidationError.new(raw_body: text, errors: errors) if errors.any?

      payload
    end
  end
end
