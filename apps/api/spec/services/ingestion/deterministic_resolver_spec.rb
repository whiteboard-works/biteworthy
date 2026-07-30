require "rails_helper"

RSpec.describe Ingestion::DeterministicResolver do
  StubItem = Struct.new(:id, :name, :description, :section_name)

  let(:matcher) do
    Ingestion::IngredientMatcher.new([
      ["meat-steak",       "Steak",           "meat.steak",              []],
      ["herb-cilantro",    "Cilantro",        "herb.cilantro",           []],
      ["fruit-lime",       "Lime",            "fruit.lime",              []],
      ["condiment-caesar", "Caesar Dressing", "condiment.caesar_dressing", []],
    ])
  end

  def resolve(*items) = described_class.call(items, matcher: matcher)

  it "writes string-keyed payload rows with slug/confidence/source" do
    result = resolve(StubItem.new("id-1", "Taco", "Grilled steak, cilantro, lime", "Tacos")).first

    expect(result.ingredients).to include(
      { "slug" => "meat-steak", "confidence" => 1.0, "source" => "match" }
    )
    expect(result.tags).to include(
      { "slug" => "grilled", "confidence" => 0.9, "source" => "match" }
    )
    expect(result.item_id).to eq("id-1")
  end

  it "is not a gap item when everything matched and nothing was left over" do
    result = resolve(StubItem.new("id-1", "Steak", "steak, cilantro, lime", nil)).first
    expect(result.gap?).to be(false)
    expect(result.gap_phrases).to be_empty
  end

  it "flags a gap when nothing matched" do
    result = resolve(StubItem.new("id-1", "Mystery Bowl", nil, nil)).first
    expect(result.gap?).to be(true)
    expect(result.gap_phrases).to contain_exactly("mystery bowl")
  end

  it "flags a gap when unknown phrases were left over" do
    result = resolve(StubItem.new("id-1", "Steak", "steak, chimichurri", nil)).first
    expect(result.gap?).to be(true)
    expect(result.gap_phrases).to contain_exactly("chimichurri")
  end

  it "ignores dish-name leftovers when the description carried matches" do
    result = resolve(StubItem.new("id-1", "Taco", "steak, cilantro, lime", nil)).first
    expect(result.gap?).to be(false)
    expect(result.gap_phrases).to be_empty
  end

  it "counts name leftovers when the description matched nothing" do
    result = resolve(StubItem.new("id-1", "Caesar Salad", "a local favorite", nil)).first
    expect(result.gap?).to be(true)
    expect(result.gap_phrases).to include("caesar salad")
  end

  it "flags a gap when a matched ingredient is a composite condiment" do
    result = resolve(StubItem.new("id-1", "Caesar Dressing", nil, nil)).first
    expect(result.ingredients.map { |r| r["slug"] }).to eq(["condiment-caesar"])
    expect(result.gap?).to be(true)
  end

  it "resolves one result per item, in order" do
    results = resolve(
      StubItem.new("a", "Steak", nil, nil),
      StubItem.new("b", "Lime", nil, nil)
    )
    expect(results.map(&:item_id)).to eq(%w[a b])
  end
end
