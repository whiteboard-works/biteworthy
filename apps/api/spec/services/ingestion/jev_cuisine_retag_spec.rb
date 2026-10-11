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
  # Mexican to the arepas by hand; the pizza's Italian came from the
  # section keyword, the way TagDeriver writes it.
  let!(:tacos)  { create(:item, restaurant: restaurant, menu_section: section, name: "Carnitas Tacos", status: "published", confidence: "confirmed", position: 0) }
  let!(:arepas) { create(:item, restaurant: restaurant, menu_section: section, name: "Arepas", status: "published", confidence: "suggested", position: 1) }
  let!(:pizza)  { create(:item, restaurant: restaurant, menu_section: section, name: "Margherita", status: "published", position: 2) }
  let!(:draft)  { create(:item, restaurant: restaurant, name: "Secret Dish", status: "draft", position: 3) }

  before do
    ItemTag.create!(item: tacos, tag: italian, source: "ai", confidence: "suggested")
    ItemTag.create!(item: tacos, tag: spicy, source: "human", confidence: "confirmed")
    ItemTag.create!(item: arepas, tag: mexican, source: "human", confidence: "confirmed")
    ItemTag.create!(item: pizza, tag: italian, source: "derived", confidence: "suggested")
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
  end

  def stub_jev(answers, status: 200)
    stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .to_return(status: status, body: { model: "jev-1.13.0", answers: answers, usage: { input_tokens: 300 } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  let(:answers) do
    { "i0__any"             => { "type" => "noul", "noul" => 0.99 },
      "i1__any"             => { "type" => "noul", "noul" => 0.99 },
      "i2__any"             => { "type" => "noul", "noul" => 0.99 },
      "i0__cuisine-mexican" => { "type" => "noul", "noul" => 0.95 },
      "i0__cuisine-italian" => { "type" => "noul", "noul" => 0.04 },
      "i1__cuisine-mexican" => { "type" => "noul", "noul" => 0.30 },
      "i1__cuisine-italian" => { "type" => "noul", "noul" => 0.02 },
      "i2__cuisine-mexican" => { "type" => "noul", "noul" => 0.01 },
      "i2__cuisine-italian" => { "type" => "noul", "noul" => 0.20 } }
  end

  def cuisine_rows(item)
    item.reload.item_tags.map { |r| [ r.tag.slug, r.source, r.confidence ] }
  end

  it "replaces model-written cuisine rows with Jev's and leaves every other row alone" do
    request = stub_jev(answers)
    result  = described_class.new(restaurant, tagger: tagger).call

    # Only the published dishes went to Jev, in position order.
    expect(request.with { |req|
      JSON.parse(req.body)["state"]["items"].map { |i| i["name"] } == [ "Carnitas Tacos", "Arepas", "Margherita" ]
    }).to have_been_made.once

    expect(cuisine_rows(tacos)).to contain_exactly(
      [ "cuisine-mexican", "ai", "suggested" ],
      [ "flavor-spicy", "human", "confirmed" ]
    )
    expect(tacos.denormalized_tag_ids).to contain_exactly(mexican.id, spicy.id)
    # Cuisine has no say in what strict-mode users see.
    expect(tacos.confidence).to eq("confirmed")

    # Jev said 0.30 to Mexican for the arepas, but a person added that tag.
    expect(cuisine_rows(arepas)).to eq([ [ "cuisine-mexican", "human", "confirmed" ] ])
    # Jev said 0.20 to Italian for the pizza, but the menu's own wording
    # said it, and gap-fill keeps those hits beside Jev's answers too.
    expect(cuisine_rows(pizza)).to eq([ [ "cuisine-italian", "derived", "suggested" ] ])
    expect(draft.reload.item_tags).to be_empty

    expect(result.dishes).to eq(3)
    expect(result.changes.map { |c| [ c.item.name, c.before, c.after ] }).to eq([
      [ "Carnitas Tacos",
        [ { slug: "cuisine-italian", confidence: "suggested" } ],
        [ { slug: "cuisine-mexican", confidence: "suggested" } ] ]
    ])
    expect(result.changes.map(&:regrade)).to eq([ false ])
    expect(result.unchanged).to eq(2)
    expect(result.unanswered).to eq(0)
  end

  it "reports a regrade of an existing row as a change: below 0.8 lands as inferred" do
    ItemTag.find_by!(item: tacos, tag: italian).destroy!
    ItemTag.create!(item: tacos, tag: mexican, source: "ai", confidence: "suggested")
    answers["i0__cuisine-mexican"]["noul"] = 0.6
    stub_jev(answers)
    result = described_class.new(restaurant, tagger: tagger).call

    expect(cuisine_rows(tacos)).to include([ "cuisine-mexican", "ai", "inferred" ])
    expect(result.changes.map { |c| [ c.regrade, c.before, c.after ] }).to eq([ [
      true,
      [ { slug: "cuisine-mexican", confidence: "suggested" } ],
      [ { slug: "cuisine-mexican", confidence: "inferred" } ]
    ] ])
  end

  it "does not write to a dish whose rows already match, so its updated_at stays put" do
    ItemTag.find_by!(item: tacos, tag: italian).update!(tag: mexican)
    stub_jev(answers)
    stamp = tacos.reload.updated_at

    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.changes).to be_empty
    expect(result.unchanged).to eq(3)
    expect(tacos.reload.updated_at).to eq(stamp)
  end

  it "reports the same changes on a dry run and writes none of them" do
    stub_jev(answers)
    result = described_class.new(restaurant, tagger: tagger).call(dry_run: true)

    expect(result.dry_run).to be(true)
    expect(result.changes.map { |c| c.after }).to eq([ [ { slug: "cuisine-mexican", confidence: "suggested" } ] ])
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "leaves a dish Jev did not fully answer as it was, and counts it" do
    answers.delete("i0__cuisine-mexican")
    stub_jev(answers)
    allow(Rails.error).to receive(:report)
    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.unanswered).to eq(1)
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "skips a dish edited while Jev was answering, since the answer was about the old text" do
    stub_request(:post, "https://api.typesafe.ai/v1/systemone").to_return do
      tacos.update!(name: "Carnitas Tacos (new recipe)")
      { status: 200, body: { model: "jev-1.13.0", answers: answers }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.stale).to eq(1)
    expect(result.changes).to be_empty
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  # An unpublish or a tag edit changes nothing Jev was told, but the row
  # moved under the question, and a removed dish must not be re-tagged.
  it "skips a dish unpublished while Jev was answering" do
    stub_request(:post, "https://api.typesafe.ai/v1/systemone").to_return do
      tacos.update!(status: "removed")
      { status: 200, body: { model: "jev-1.13.0", answers: answers }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.stale).to eq(1)
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  # A section rename goes through the section row, not the dishes, so a
  # dish timestamp would not catch it.
  it "skips every dish whose section was renamed while Jev was answering" do
    stub_request(:post, "https://api.typesafe.ai/v1/systemone").to_return do
      section.update!(name: "Antipasti")
      { status: 200, body: { model: "jev-1.13.0", answers: answers }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    result = described_class.new(restaurant, tagger: tagger).call

    expect(result.stale).to eq(3)
    expect(result.changes).to be_empty
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "writes nothing when Jev fails, and says so" do
    stub_jev({}, status: 401)
    allow(Rails.error).to receive(:report)

    expect { described_class.new(restaurant, tagger: tagger).call }.to raise_error(described_class::Unavailable)
    expect(cuisine_rows(tacos).map(&:first)).to contain_exactly("cuisine-italian", "flavor-spicy")
  end

  it "refuses outright when the taxonomy has no leaf cuisine tags, rather than reporting every dish unanswered" do
    Tag.where(family: "cuisine").find_each { |t| t.item_tags.destroy_all; t.destroy! }
    jev = stub_jev({})

    expect { described_class.new(restaurant, tagger: tagger).call }
      .to raise_error(described_class::Unavailable, /no leaf cuisine tags/)
    expect(jev).not_to have_been_made
  end
end
