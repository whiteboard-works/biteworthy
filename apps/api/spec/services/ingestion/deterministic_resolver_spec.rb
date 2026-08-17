require "rails_helper"

RSpec.describe Ingestion::DeterministicResolver do
  StubItem = Struct.new(:id, :name, :description, :section_name)

  let(:matcher) do
    Ingestion::IngredientMatcher.new([
      ["meat-steak",       "Steak",           "meat.steak",              []],
      ["herb-cilantro",    "Cilantro",        "herb.cilantro",           []],
      ["fruit-lime",       "Lime",            "fruit.lime",              []],
      ["condiment-caesar", "Caesar Dressing", "condiment.caesar_dressing", []],
      ["dairy-mozzarella", "Mozzarella",      "dairy.mozzarella",        []],
      ["herb-basil",       "Basil",           "herb.basil",              []],
      ["poultry-chicken",  "Chicken",         "poultry.chicken",         []],
      ["fruit-lemon",      "Lemon",           "fruit.lemon",             []],
      ["grain-wheat",      "Wheat",           "grain.wheat",             []],
      ["grain-wheat-flour-tortilla", "Flour Tortilla", "grain.wheat.flour_tortilla", []],
      ["grain-wheat-pasta", "Pasta",          "grain.wheat.pasta",       []],
      ["grain-corn-tortilla", "Corn Tortilla", "grain.corn.tortilla",    []],
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

  # The pizza bug (ux-exploration finding 1): a composed dish whose
  # description resolves cleanly used to skip inference entirely, so the
  # wheat crust never existed and gluten-free passed the pizzas.
  describe "implied bases for composed dishes" do
    it "unions the base ingredient and still routes a cleanly-resolved dish to gap-fill" do
      result = resolve(StubItem.new("id-1", "Margherita Pizza", "mozzarella, basil", nil)).first

      expect(result.ingredients).to include(
        { "slug" => "grain-wheat", "confidence" => 0.8, "source" => "derived" }
      )
      # The implied base must feed allergen derivation, or the filter
      # still can't hide the pizza from gluten-free users.
      expect(result.tags).to include(
        { "slug" => "contains-gluten", "confidence" => 0.8, "source" => "derived" }
      )
      expect(result.gap?).to be(true)
      expect(result.gap_phrases).to be_empty
    end

    it "does not invent bases for a plain dish" do
      result = resolve(StubItem.new("id-1", "Grilled Chicken", "chicken, lemon", nil)).first

      expect(result.ingredients.map { |r| r["slug"] })
        .to contain_exactly("poultry-chicken", "fruit-lemon")
      expect(result.gap?).to be(false)
      expect(result.gap_phrases).to be_empty
    end

    it "skips the union when an explicit match already covers the base subtree, but still gap-fills" do
      result = resolve(StubItem.new("id-1", "Quesadilla", "flour tortilla, chicken", nil)).first

      expect(result.ingredients.map { |r| r["slug"] })
        .to contain_exactly("grain-wheat-flour-tortilla", "poultry-chicken")
      expect(result.gap?).to be(true)
    end

    # Knowingly the false-positive direction: no suppressor for the
    # explicit corn base. Hidden-with-reason + show-anyway + the model
    # pass (which sees "corn tortilla") + human verify make a wrong
    # derived wheat recoverable; a silent pass on a real crust is not.
    it "still derives wheat for a corn-tortilla quesadilla, and routes it to gap-fill" do
      result = resolve(StubItem.new("id-1", "Quesadilla", "corn tortilla, chicken", nil)).first

      expect(result.ingredients).to include(
        { "slug" => "grain-wheat", "confidence" => 0.8, "source" => "derived" }
      )
      expect(result.ingredients.map { |r| r["slug"] }).to include("grain-corn-tortilla")
      expect(result.gap?).to be(true)
    end

    it "routes on a section keyword but never unions from it (sections go to the model)" do
      result = resolve(StubItem.new("id-1", "Margherita", "mozzarella, basil", "Pizzas")).first

      expect(result.ingredients.map { |r| r["slug"] }).not_to include("grain-wheat")
      expect(result.gap?).to be(true)
    end

    it "suppresses the base when the dish's own name claims the diet it would contradict" do
      result = resolve(StubItem.new("id-1", "Gluten-Free Pizza", "mozzarella, basil", nil)).first

      expect(result.ingredients.map { |r| r["slug"] }).not_to include("grain-wheat")
      # The explicit claim must survive — unioning wheat here would veto
      # it and hide the dish from exactly the users it exists for.
      expect(result.tags.map { |t| t["slug"] }).to include("gluten-free")
      expect(result.gap?).to be(true)
    end

    # The claim also beats the name's own catalog evidence ("pasta"
    # matches the catalog inside the name). Whether THIS dish's penne is
    # a wheat or GF shape is exactly the ambiguity the model pass gets
    # to judge — the deterministic layer keeps the claim viable.
    it "keeps a gluten-free claim viable over name-derived evidence (Gluten-Free Pasta)" do
      result = resolve(StubItem.new("id-1", "Gluten-Free Pasta", "penne, marinara", nil)).first

      expect(result.ingredients.map { |r| r["slug"] })
        .not_to include("grain-wheat", "grain-wheat-pasta")
      expect(result.tags.map { |t| t["slug"] }).to include("gluten-free")
      expect(result.gap?).to be(true)
    end

    it "lets explicit description evidence beat the claim (a listed flour tortilla is not GF)" do
      result = resolve(StubItem.new("id-1", "Gluten-Free Wrap", "flour tortilla", nil)).first

      expect(result.ingredients.map { |r| r["slug"] }).to include("grain-wheat-flour-tortilla")
      expect(result.tags.map { |t| t["slug"] }).to include("contains-gluten")
      expect(result.tags.map { |t| t["slug"] }).not_to include("gluten-free")
    end

    it "keeps the base under a claim it doesn't contradict (a vegan burger still has a bun)" do
      result = resolve(StubItem.new("id-1", "Vegan Burger", "basil", nil)).first

      expect(result.ingredients.map { |r| r["slug"] }).to include("grain-wheat")
    end

    it "matches plural, identity-plural, and multi-word dish-name keywords" do
      pizzas, lo_mein, focaccias = resolve(
        StubItem.new("a", "Margherita Pizzas", "mozzarella, basil", nil),
        StubItem.new("b", "Chicken Lo Mein", "chicken", nil),
        StubItem.new("c", "House Focaccias", "basil", nil)
      )

      expect(pizzas.ingredients.map { |r| r["slug"] }).to include("grain-wheat")
      expect(lo_mein.ingredients.map { |r| r["slug"] }).to include("grain-wheat")
      # "focaccia".pluralize is identity (the -ia Latin-plural rule), so
      # the plural is listed explicitly in the keyword table.
      expect(focaccias.ingredients.map { |r| r["slug"] }).to include("grain-wheat")
    end
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
