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
end
