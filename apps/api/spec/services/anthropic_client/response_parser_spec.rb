require "rails_helper"

RSpec.describe AnthropicClient::ResponseParser do
  # Minimal schema: an object with a required boolean `ok`.
  let(:schema) do
    {
      "type" => "object",
      "required" => ["ok"],
      "properties" => { "ok" => { "type" => "boolean" } }
    }
  end

  # Single-array-property object schema, the shape bare-array coercion
  # targets (previously exercised via the deleted Ingestion::ResolutionSchema).
  let(:items_schema) do
    {
      "type" => "object",
      "required" => ["items"],
      "properties" => {
        "items" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => %w[index resolved unresolved],
            "properties" => {
              "index"      => { "type" => "integer" },
              "resolved"   => { "type" => "array" },
              "unresolved" => { "type" => "array" }
            }
          }
        }
      }
    }
  end

  it "parses plain strict JSON" do
    expect(described_class.parse_and_validate('{"ok":true}', schema)).to eq("ok" => true)
  end

  it "parses JSON wrapped in a ```json markdown fence (the live resolve failure)" do
    text = "```json\n{\"ok\": true}\n```"
    expect(described_class.parse_and_validate(text, schema)).to eq("ok" => true)
  end

  it "parses JSON wrapped in a bare ``` fence" do
    text = "```\n{\"ok\": false}\n```"
    expect(described_class.parse_and_validate(text, schema)).to eq("ok" => false)
  end

  it "still raises ValidationError on genuinely malformed JSON" do
    expect { described_class.parse_and_validate("not json at all", schema) }
      .to raise_error(AnthropicClient::ValidationError, /JSON parse failed/)
  end

  it "still raises ValidationError on schema mismatch" do
    expect { described_class.parse_and_validate('{"ok":"not a bool"}', schema) }
      .to raise_error(AnthropicClient::ValidationError)
  end

  describe "bare-array coercion" do
    it "wraps a bare array under the schema's single array property so it validates" do
      # The live resolve failure: model returned [...] instead of {items:[...]}
      # ("property '#/' of type array did not match ... object").
      result = described_class.parse_and_validate(
        '[{"index":0,"resolved":[],"unresolved":[]}]',
        items_schema
      )
      expect(result["items"].first).to include("index" => 0)
    end

    it "coerces a bare array that is also markdown-fenced" do
      result = described_class.parse_and_validate(
        "```json\n[{\"index\":0,\"resolved\":[],\"unresolved\":[]}]\n```",
        items_schema
      )
      expect(result["items"].size).to eq(1)
    end

    it "does NOT wrap when the schema isn't a single-array object (still fails)" do
      # `schema` here is {ok: boolean} — no array property, so a bare array
      # stays an array and fails validation rather than being force-wrapped.
      expect { described_class.parse_and_validate('[1, 2]', schema) }
        .to raise_error(AnthropicClient::ValidationError)
    end
  end
end
