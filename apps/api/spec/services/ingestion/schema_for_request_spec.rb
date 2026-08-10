require "rails_helper"

# Structured outputs constrain what the model may emit, rather than asking
# for JSON in prose and checking afterwards. They accept a subset of JSON
# Schema, so the wire form is derived from the validator rather than
# hand-written — two schemas would drift, and silently: a wire schema
# missing a field still produces valid-looking output, just without it.
RSpec.describe Ingestion::SchemaForRequest do
  subject(:derived) { described_class.derive(Ingestion::MenuExtractionSchema) }

  it "drops the keywords structured outputs reject" do
    serialized = derived.to_s

    expect(serialized).not_to include("minLength")
    expect(serialized).not_to include("minimum")
    expect(serialized).not_to include("maximum")
    expect(serialized).not_to include("exclusiveMinimum")
  end

  # `oneOf` is unsupported; `anyOf` is. They mean the same thing for these
  # branches, which are disjoint by construction — a null or a
  # fully-specified object — so "exactly one" and "at least one" cannot
  # disagree.
  it "rewrites oneOf as anyOf" do
    expect(Ingestion::MenuExtractionSchema.to_s).to include("oneOf")
    expect(derived.to_s).not_to include("oneOf")

    bbox = derived.dig(:properties, :sections, :items, :properties, :items,
                       :items, :properties, :image_bbox)
    expect(bbox.keys).to eq([ :anyOf ])
    expect(bbox[:anyOf].map { |b| b[:type] }).to eq([ "null", "object" ])
  end

  it "keeps the structure the model is being constrained to" do
    item = derived.dig(:properties, :sections, :items, :properties, :items, :items)

    expect(item[:required]).to eq([ "name" ])
    expect(item[:additionalProperties]).to be(false)
    expect(item[:properties].keys).to include(:name, :description, :prices, :addons)
  end

  # The point of stripping is that nothing is *lost* — the value rules
  # move from the wire to the post-hoc validator, which still runs.
  it "leaves the validating schema untouched" do
    described_class.derive(Ingestion::MenuExtractionSchema)

    expect(Ingestion::MenuExtractionSchema.to_s).to include("minLength")
  end

  # The property that actually matters: anything the constrained model can
  # emit must still satisfy the full schema, or extraction would fail
  # validation on its own well-formed output.
  it "produces a schema whose conforming output the full schema accepts" do
    payload = {
      "sections" => [
        { "name" => "Tacos",
          "items" => [
            { "name" => "Carne Asada", "description" => "Grilled steak.",
              "prices" => [ { "size" => nil, "price_cents" => 450 } ],
              "addons" => [ { "name" => "Add chicken", "price_cents" => 300 } ],
              "image_bbox" => nil }
          ] }
      ]
    }

    expect(JSON::Validator.fully_validate(derived, payload)).to be_empty
    expect(JSON::Validator.fully_validate(Ingestion::MenuExtractionSchema, payload)).to be_empty
  end
end
