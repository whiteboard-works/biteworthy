require "rails_helper"

RSpec.describe Ingestion::JevCuisineRetag do
  let(:restaurant) { create(:restaurant, :published) }
  let(:section)    { create(:menu_section, menu: create(:menu, restaurant: restaurant), name: "Mains") }
  let(:client)     { TypesafeClient.new(api_key: "test-key", model: "jev-latest") }
  let(:tagger)     { Ingestion::JevCuisineTagger.new(client: client) }

  let!(:mexican)  { create(:tag, slug: "cuisine-mexican") }
  let!(:italian)  { create(:tag, slug: "cuisine-italian") }
  let!(:spicy)    { create(:tag, slug: "flavor-spicy") }

  # Haiku called the tacos Italian; a person confirmed spicy and added
  # Mexican to the arepas by hand.
  let!(:tacos)  { create(:item, restaurant: restaurant, menu_section: section, name: "Carnitas Tacos", status: "published", confidence: "confirmed", position: 0) }
  let!(:arepas) { create(:item, restaurant: restaurant, menu_section: section, name: "Arepas", status: "published", confidence: "suggested", position: 1) }
  let!(:draft)  { create(:item, restaurant: restaurant, name: "Secret Dish", status: "draft", position: 2) }

  before do
    ItemTag.create!(item: tacos, tag: italian, source: "ai", confidence: "suggested")
    ItemTag.create!(item: tacos, tag: spicy, source: "human", confidence: "confirmed")
    ItemTag.create!(item: arepas, tag: mexican, source: "human", confidence: "confirmed")
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  def stub_jev(answers, status: 200)
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: status, body: { model: "jev-1.13.0", answers: answers, usage: { input_tokens: 300 } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  let(:answers) do
    { "i0__cuisine-mexican" => { "type" => "noul", "noul" => 0.95 },
      "i0__cuisine-italian" => { "type" => "noul", "noul" => 0.04 },
      "i1__cuisine-mexican" => { "type" => "noul", "noul" => 0.30 },
      "i1__cuisine-italian" => { "type" => "noul", "noul" => 0.02 } }
  end

  it "replaces machine cuisine rows with Jev's, keeps what a person vouched for, and touches nothing else" do
    request = stub_jev(answers)
    result  = described_class.new(restaurant, tagger: tagger).call

    # Only the published dishes went to Jev, in position order.
    expect(request.with { |req| JSON.parse(req.body)["state"]["items"].map { |i| i["name"] } == [ "Carnitas Tacos", "Arepas" ] })
      .to have_been_made.once

    tacos.reload
    expect(tacos.item_tags.map { |r| [ r.tag.slug, r.source, r.confidence ] }).to contain_exactly(
      [ "cuisine-mexican", "ai", "suggested" ],
      [ "flavor-spicy", "human", "confirmed" ]
    )
    expect(tacos.denormalized_tag_ids).to contain_exactly(mexican.id, spicy.id)
    # Cuisine has no say in what strict-mode users see.
    expect(tacos.confidence).to eq("confirmed")

    # Jev said 0.30 to Mexican for the arepas, but a person added that tag.
    expect(arepas.reload.item_tags.map { |r| [ r.tag.slug, r.source ] }).to eq([ [ "cuisine-mexican", "human" ] ])
    expect(draft.reload.item_tags).to be_empty

    expect(result.dishes).to eq(2)
    expect(result.changes.map { |c| [ c.item.name, c.before, c.after ] })
      .to eq([ [ "Carnitas Tacos", [ "cuisine-italian" ], [ "cuisine-mexican" ] ] ])
    expect(result.unchanged).to eq(1)
    expect(result.unanswered).to eq(0)
  end

  it "stores the probability's grade: below 0.8 lands as inferred" do
    answers["i0__cuisine-mexican"]["noul"] = 0.6
    stub_jev(answers)
    described_class.new(restaurant, tagger: tagger).call

    expect(tacos.reload.item_tags.find_by(tag: mexican).confidence).to eq("inferred")
  end

  it "reports the same changes on a dry run and writes none of them" do
    stub_jev(answers)
    result = described_class.new(restaurant, tagger: tagger).call(dry_run: true)

    expect(result.dry_run).to be(true)
    expect(result.changes.map { |c| c.after }).to eq([ [ "cuisine-mexican" ] ])
    expect(tacos.reload.item_tags.map { |r| r.tag.slug }).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "leaves a dish Jev did not fully answer as it was, and counts it" do
    answers.delete("i0__cuisine-mexican")
    stub_jev(answers)
    allow(Rails.error).to receive(:report)
    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.unanswered).to eq(1)
    expect(tacos.reload.item_tags.map { |r| r.tag.slug }).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "writes nothing when Jev fails, and says so" do
    stub_jev({}, status: 401)
    allow(Rails.error).to receive(:report)

    expect { described_class.new(restaurant, tagger: tagger).call }.to raise_error(described_class::Unavailable)
    expect(tacos.reload.item_tags.map { |r| r.tag.slug }).to contain_exactly("cuisine-italian", "flavor-spicy")
  end
end
