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
      payload = coerce_root(JSON.parse(strip_code_fence(text)), schema)
    rescue JSON::ParserError => e
      raise AnthropicClient::ValidationError.new(
        raw_body: text, errors: ["JSON parse failed: #{e.message}"]
      )
    else
      errors = JSON::Validator.fully_validate(schema, payload)
      raise AnthropicClient::ValidationError.new(raw_body: text, errors: errors) if errors.any?

      payload
    end

    # Despite the "STRICT JSON ONLY, no fences" system instruction, the
    # model sometimes wraps its response in a ```json … ``` markdown fence
    # (seen live in the resolve stage: "unexpected character: '```json'").
    # Strip a surrounding fence so a well-formed body inside it still
    # parses; text without a leading fence is returned unchanged.
    def strip_code_fence(text)
      stripped = text.to_s.strip
      return stripped unless stripped.start_with?("```")

      stripped
        .sub(/\A```[a-z0-9]*[ \t]*\r?\n?/i, "") # opening ``` or ```json
        .sub(/\r?\n?```\s*\z/, "")              # closing ```
        .strip
    end

    # Models (especially faster ones) sometimes return a bare array when
    # the schema wants a single-array object like {"items":[...]} — seen
    # live at the resolve stage as "property '#/' of type array did not
    # match ... object". When the parsed value is an Array and the schema
    # is exactly one array-typed property, wrap it under that key so a
    # well-formed body still validates. Anything else passes through
    # unchanged (and genuinely-wrong shapes still fail validation).
    def coerce_root(payload, schema)
      return payload unless payload.is_a?(Array)
      return payload unless (schema[:type] || schema["type"]) == "object"

      props      = schema[:properties] || schema["properties"] || {}
      array_keys = props.select { |_, spec| (spec[:type] || spec["type"]) == "array" }.keys
      return payload unless array_keys.size == 1

      { array_keys.first.to_s => payload }
    end
  end
end
