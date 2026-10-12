require "rails_helper"

# Table-driven coverage of the deterministic matcher: the index is
# passed in directly (no DB) so each case reads as data.
RSpec.describe Ingestion::IngredientMatcher do
  let(:rows) do
    [
      ["dairy-cheese",      "Cheese",      "dairy.cheese",      %w[queso fromage]],
      ["dairy",             "Dairy",       "dairy",             []],
      ["dairy-goat-cheese", "Goat Cheese", "dairy.goat_cheese", []],
      ["meat-beef",         "Beef",        "meat.beef",         %w[steak]],
      ["meat-steak",        "Steak",       "meat.steak",        []],
      ["vegetable-tomato",  "Tomato",      "vegetable.tomato",  []],
      ["herb-cilantro",     "Cilantro",    "herb.cilantro",     %w[coriander]],
      ["fruit-lime",        "Lime",        "fruit.lime",        []],
      ["vegetable-jalapeno", "Jalapeño",   "vegetable.jalapeno", []],
      ["legume-peanuts",    "Peanuts",     "legume.peanuts",    []],
      ["vegetable-olive",   "Olive",       "vegetable.olive",   []],
      ["spice-clove",       "Clove",       "spice.clove",       []],
    ]
  end

  subject(:matcher) { described_class.new(rows) }

  def slugs(text)
    matcher.scan(text).first.map { |m| m[:slug] }
  end

  it "matches an exact catalog name at confidence 1.0" do
    matches, = matcher.scan("Tomato")
    expect(matches).to contain_exactly(
      { slug: "vegetable-tomato", path: "vegetable.tomato", confidence: 1.0, source: "match" }
    )
  end

  it "matches an alias at confidence 0.95" do
    matches, = matcher.scan("corn tortilla, queso")
    row = matches.find { |m| m[:slug] == "dairy-cheese" }
    expect(row[:confidence]).to eq(0.95)
  end

  it "bridges plurals both ways via last-word singularization" do
    expect(slugs("Tomatoes")).to include("vegetable-tomato")
    expect(slugs("peanut sauce")).to include("legume-peanuts")
  end

  # "Dairy" is the root node's own name, so "dairy-free dressing" matched
  # dairy, and "vegan cheese" would match the dairy root's "cheese" alias.
  # These phrases name the absence of the thing, so they must stay
  # leftovers for gap-fill and the reviewer, never a catalog match.
  it "never matches a phrase that names the absence of an ingredient" do
    matches, leftovers = matcher.scan("dairy-free dressing, topped with vegan cheese, non-dairy cheese")
    expect(matches.map { |m| m[:slug] }).to be_empty
    expect(leftovers).to include("vegan cheese", "non dairy cheese")
    expect(slugs("cheese-free pizza, no cheese, without cheese")).to be_empty
  end

  it "keeps the allergen when a free-from version is only on offer" do
    m = described_class.new(rows + [ ["legume-peanuts", "Peanuts", "legume.peanuts", ["peanut"]] ])
    read = ->(text) { m.scan(text).first.map { |r| r[:slug] } }

    expect(read.("pad thai, can be made peanut-free")).to include("legume-peanuts")
    expect(read.("peanut-free pad thai")).not_to include("legume-peanuts")
    expect(slugs("house-made vegan cheese, made with dairy-free cheese")).to be_empty
    expect(slugs("mac and cheese, optionally dairy-free")).to include("dairy")
  end

  it "still matches when the absence phrase is itself negated" do
    expect(slugs("this sauce is not dairy-free")).to include("dairy")
    expect(slugs("this sauce isn't dairy-free")).to include("dairy")
  end

  # "Dairy-free option available" describes a variant; the dish as served
  # still has the dairy, and Diet tagging relies on that evidence to veto
  # its own dairy-free claim.
  it "keeps the evidence when the phrase only offers an alternative" do
    expect(slugs("topped with cheese, dairy-free option available")).to include("dairy")
    expect(slugs("vegan cheese available upon request")).to include("dairy-cheese")
    expect(slugs("made with vegan butter alternative, a vegan butter substitute")).to be_empty
  end

  # ActiveSupport singularizes "olives" to "olife" and "cloves" to
  # "clofe" (the knives → knife rule), so a plural olive never matched
  # and an olive-avoider saw "tomatoes, and olives" as safe.
  it "bridges -ves plurals the inflector gets wrong" do
    expect(slugs("lettuce, cheese, tomatoes, and olives")).to include("vegetable-olive")
    expect(slugs("whole cloves")).to include("spice-clove")
  end

  it "prefers the longest phrase and consumes it (no nested bare match)" do
    expect(slugs("goat cheese, arugula")).to include("dairy-goat-cheese")
    expect(slugs("goat cheese, arugula")).not_to include("dairy-cheese")
  end

  it "splits on punctuation, connectives, and & — and folds diacritics" do
    expect(slugs("Grilled steak, cilantro & lime with jalapeños.")).to contain_exactly(
      "meat-steak", "herb-cilantro", "fruit-lime", "vegetable-jalapeno"
    )
  end

  it "keeps the best confidence when name and alias both hit the same slug" do
    matches, = matcher.scan("Cheese, extra queso")
    rows = matches.select { |m| m[:slug] == "dairy-cheese" }
    expect(rows.size).to eq(1)
    expect(rows.first[:confidence]).to eq(1.0)
  end

  it "lets a catalog name win over another ingredient's alias for the same term" do
    matches, = matcher.scan("Steak")
    expect(matches).to contain_exactly(
      hash_including(slug: "meat-steak", confidence: 1.0)
    )
  end

  it "logs and keeps the first writer on a same-kind collision" do
    allow(Rails.logger).to receive(:warn)
    colliding = rows + [["meat-flank", "Steak", "meat.flank", []]]
    m = described_class.new(colliding)
    expect(Rails.logger).to have_received(:warn).with(/maps to both/)
    expect(m.scan("Steak").first.map { |r| r[:slug] }).to eq(["meat-steak"])
  end

  it "returns unknown ingredient-looking text as leftovers, edge-trimming stopwords" do
    matches, leftovers = matcher.scan("Caesar Salad")
    expect(matches).to be_empty
    expect(leftovers).to contain_exactly("caesar salad")

    # "served", "with", "our", "house" drop; "dressing" survives.
    _, leftovers = matcher.scan("served with our house dressing")
    expect(leftovers).to contain_exactly("dressing")
  end

  it "drops pure stopword/number runs entirely" do
    _, leftovers = matcher.scan("choice of 2")
    expect(leftovers).to be_empty
  end

  it "matches catalog terms that contain connective words" do
    with_half = rows + [["dairy-half-and-half", "Half-and-Half", "dairy.half_and_half", ["half and half"]]]
    m = described_class.new(with_half)

    matches, leftovers = m.scan("mashed potatoes with half-and-half")
    expect(matches.map { |r| r[:slug] }).to include("dairy-half-and-half")
    expect(leftovers).to contain_exactly("mashed potatoes")
  end

  it "splits leftover runs on connectives so each side is its own gap phrase" do
    _, leftovers = matcher.scan("chimichurri and cotija")
    expect(leftovers).to contain_exactly("chimichurri", "cotija")
  end

  it "handles nil text" do
    matches, leftovers = matcher.scan(nil)
    expect(matches).to be_empty
    expect(leftovers).to be_empty
  end
end
