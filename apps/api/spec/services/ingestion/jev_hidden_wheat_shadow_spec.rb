require "rails_helper"

RSpec.describe Ingestion::JevHiddenWheatShadow do
  let(:run)    { create(:ingestion_run, :staged, enrichment_status: "pending") }
  let(:client) { TypesafeClient.new(api_key: "test-key", model: "jev-latest") }

  let(:rows) do
    [ { name: "Margherita Pizza", description: "tomato, mozzarella, basil", section: "Pizza" },
     { name: "Grilled Salmon", description: "with rice", section: "Mains" },
     { name: "Fish & Chips", description: nil, section: "Pub" } ]
  end
  # What gap-fill actually merged: the pizza got its crust, the salmon
  # nothing wheaten, and Haiku missed the batter on the fish.
  let(:merged) do
    { 0 => [ { "slug" => "grain-wheat-crust", "confidence" => 0.9, "source" => "ai" } ],
      1 => [ { "slug" => "fish-salmon", "confidence" => 0.95, "source" => "match" } ],
      2 => [ { "slug" => "fish-cod", "confidence" => 0.95, "source" => "match" } ] }
  end
  let(:paths) { { "grain-wheat-crust" => "grain.wheat.crust", "fish-salmon" => "fish.salmon", "fish-cod" => "fish.cod" } }

  let(:answers) do
    { "i0__wheat" => { "type" => "noul", "noul" => 0.97 },
      "i1__wheat" => { "type" => "noul", "noul" => 0.04 },
      "i2__wheat" => { "type" => "noul", "noul" => 0.91 } }
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  def stub_jev(status: 200, body: { model: "jev-1.13.0", answers: answers, usage: { input_tokens: 350 } })
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "records the slice as an observation, with the dangerous disagreement named" do
    request = stub_jev
    described_class.new(client: client).call(run, rows, merged, paths, attempt: 1)

    expect(request.with { |req|
      body = JSON.parse(req.body)
      body["questions"].keys == %w[i0__wheat i1__wheat i2__wheat] &&
        body["questions"]["i0__wheat"]["criteria"]["true"]["examples"].include?("margherita pizza") &&
        body["state"]["items"].map { |i| i["name"] } == [ "Margherita Pizza", "Grilled Salmon", "Fish & Chips" ]
    }).to have_been_made.once

    row = JevObservation.find_by!(kind: "hidden_wheat_shadow", subject: run)
    expect(row).to have_attributes(outcome: "answered", agree: false, model: "jev-1.13.0", input_tokens: 350)
    expect(row.details).to include("items" => 3, "agree" => 2, "jev_only" => 1, "data_only" => 0, "missing" => 0,
                                   "attempt" => 1)
    expect(row.details["disagreements"]).to eq([
      { "index" => 2, "item" => "Fish & Chips", "section" => "Pub", "jev" => 0.91, "data" => false }
    ])
  end

  it "agrees when the data already carries the wheat Jev expects" do
    merged[2] << { "slug" => "grain-wheat-batter", "confidence" => 0.8, "source" => "ai" }
    paths["grain-wheat-batter"] = "grain.wheat.batter"
    stub_jev
    described_class.new(client: client).call(run, rows, merged, paths)

    expect(JevObservation.find_by!(kind: "hidden_wheat_shadow", subject: run)).to have_attributes(agree: true)
  end

  # It runs inside GapFillResolveJob between a billed Haiku call and the
  # next slice; a shadow must never hand retry_on a reason to re-bill.
  it "never raises, and keeps a failed observation" do
    stub_jev(status: 503, body: {})

    result = nil
    expect { result = described_class.new(client: client).call(run, rows, merged, paths) }.not_to raise_error
    expect(result).to be(false)
    expect(JevObservation.find_by!(kind: "hidden_wheat_shadow", subject: run))
      .to have_attributes(outcome: "failed", agree: nil)
  end

  # An item accepted while Haiku was answering is skipped by the merge and
  # has no merged rows; that is not "no wheat".
  it "counts a dish the merge skipped as skipped, not as a disagreement" do
    merged.delete(2)
    stub_jev
    expect(described_class.new(client: client).call(run, rows, merged, paths)).to be(true)

    row = JevObservation.find_by!(kind: "hidden_wheat_shadow", subject: run)
    expect(row.details).to include("skipped" => 1, "jev_only" => 0, "agree" => 2)
    expect(row.agree).to be(true)
  end

  it "writes nothing to any dish" do
    stub_jev
    expect { described_class.new(client: client).call(run, rows, merged, paths) }
      .not_to change { IngestionItem.pluck(:ingredients_payload, :tags_payload) }
  end
end
