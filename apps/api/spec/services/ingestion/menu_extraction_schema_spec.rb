require "rails_helper"
require "json-schema"

# Phase 4.11.2 — guards the structural schema change that lets
# Anthropic vision return a per-dish bbox alongside the text fields.
# The validator runs through AnthropicClient::ResponseParser at runtime,
# but the rules belong to the schema constant — so this spec hits it
# directly to keep failures pinpointed.
RSpec.describe Ingestion::MenuExtractionSchema do
  let(:schema) { described_class }

  def validate(payload)
    JSON::Validator.fully_validate(schema, payload)
  end

  let(:base_item) do
    {
      "name"        => "Spring Rolls",
      "description" => "Crispy veggie rolls.",
      "prices"      => [{ "size" => nil, "price_cents" => 600 }]
    }
  end

  let(:base_payload) do
    { "sections" => [{ "name" => "Appetizers", "items" => [base_item] }] }
  end

  it "accepts a payload with no image_bbox (text-only menu)" do
    expect(validate(base_payload)).to be_empty
  end

  it "accepts a well-formed image_bbox" do
    item = base_item.merge("image_bbox" => { "x" => 0.5, "y" => 0.1, "w" => 0.2, "h" => 0.15 })
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    expect(validate(payload)).to be_empty
  end

  it "accepts a null image_bbox (some models prefer null over omission)" do
    item = base_item.merge("image_bbox" => nil)
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    expect(validate(payload)).to be_empty
  end

  it "rejects an image_bbox missing a key" do
    item = base_item.merge("image_bbox" => { "x" => 0.5, "y" => 0.1, "w" => 0.2 })
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    errors = validate(payload)
    expect(errors).not_to be_empty
    expect(errors.join("\n")).to match(/required.*h|h.*required/i)
  end

  it "rejects an image_bbox with x out of [0,1]" do
    item = base_item.merge("image_bbox" => { "x" => 1.5, "y" => 0.1, "w" => 0.2, "h" => 0.2 })
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    expect(validate(payload)).not_to be_empty
  end

  it "rejects an image_bbox with zero width (exclusiveMinimum)" do
    item = base_item.merge("image_bbox" => { "x" => 0.1, "y" => 0.1, "w" => 0, "h" => 0.2 })
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    expect(validate(payload)).not_to be_empty
  end

  it "rejects an unknown property in image_bbox (additionalProperties: false)" do
    item = base_item.merge(
      "image_bbox" => { "x" => 0.1, "y" => 0.1, "w" => 0.2, "h" => 0.2, "rotation" => 5 }
    )
    payload = { "sections" => [{ "name" => "Appetizers", "items" => [item] }] }
    expect(validate(payload)).not_to be_empty
  end
end
