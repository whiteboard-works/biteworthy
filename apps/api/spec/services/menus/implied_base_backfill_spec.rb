require "rails_helper"

# Dishes promoted before a gluten rule existed (#638, #766, #794) never
# got the row it adds, so a Celiac filter still shows them. The backfill
# applies today's rules to them. It must only ever add: a wrong wheat
# row hides a dish with a reason a person can fix, while a missing one
# fails silently, which is the failure this exists to stop. And it must
# never put back a row a person removed.
RSpec.describe Menus::ImpliedBaseBackfill do
  include ActiveSupport::Testing::TimeHelpers

  let!(:wheat)       { create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat") }
  let!(:barley)      { create(:ingredient, slug: "grain-barley", name: "Barley", path: "grain.barley") }
  let!(:wheat_bread) { create(:ingredient, slug: "grain-wheat-bread", name: "Bread", path: "grain.wheat.bread") }
  let!(:potato)      { create(:ingredient, slug: "veg-potato", name: "Potato", path: "veg.potato") }
  let!(:gravy) do
    create(:ingredient, slug: "grain-wheat-gravy", name: "Wheat-Based Gravy",
                        path: "grain.wheat.gravy", aliases: [ "country gravy" ])
  end
  let!(:breading) do
    create(:ingredient, slug: "grain-wheat-breading", name: "Breading",
                        path: "grain.wheat.breading", aliases: [ "breaded" ])
  end
  let!(:gluten_tag) { create(:tag, slug: "contains-gluten", name: "Contains Gluten", family: "allergen") }

  def live(pr) = described_class::RULE_SETS.find { |rs| rs.pr == pr }.live_since

  # Every dish here predates all three rule sets unless a test says otherwise.
  around { |ex| travel_to(live(638) - 1.day) { ex.run } }

  def created_at!(item, time) = item.tap { |i| i.update_columns(created_at: time, updated_at: time) }
  def run(apply: true) = described_class.call(apply: apply)

  # A keyword added to the resolver without a rule set here would never
  # reach old dishes.
  it "covers every implied-base keyword the resolver knows, in exactly one rule set" do
    listed = described_class::RULE_SETS.flat_map(&:name_keywords)
    expect(listed).to match_array(Ingestion::DeterministicResolver::IMPLIED_BASE_KEYWORDS.fetch("grain-wheat"))
    expect(Ingestion::DeterministicResolver::IMPLIED_BASE_KEYWORDS.keys).to eq([ "grain-wheat" ])
  end

  it "covers every gluten implication the resolver knows" do
    listed = described_class::RULE_SETS.map(&:implications).reduce({}, :merge)
    expect(listed).to eq(Ingestion::DeterministicResolver::GLUTEN_IMPLICATIONS)
  end

  it "adds a derived, suggested wheat row and the gluten tag to a samosa" do
    samosa = create(:item, :published, :confirmed, name: "Vegetable Samosa", ingredients: [ potato ])

    result = run

    expect(result.changes.map(&:item_id)).to eq([ samosa.id ])
    expect(samosa.item_ingredients.find_by!(ingredient: wheat))
      .to have_attributes(source: "derived", confidence: "suggested")
    expect(samosa.item_tags.find_by!(tag: gluten_tag))
      .to have_attributes(source: "ingredient_derived", confidence: "suggested")
    samosa.reload
    # The filter reads the denormalized arrays; this is what hides it.
    expect(samosa.denormalized_ingredient_ids).to include(wheat.id)
    expect(samosa.denormalized_tag_ids).to include(gluten_tag.id)
  end

  # Item confidence is the weakest link. A confirmed dish with a
  # suggested row is no longer confirmed, so Strict mode hides it too.
  it "lowers a confirmed dish to suggested, and never raises an inferred one" do
    confirmed = create(:item, :published, :confirmed, name: "Samosa")
    inferred  = create(:item, :published, name: "Chile Relleno", confidence: "inferred")

    run

    expect(confirmed.reload.confidence).to eq("suggested")
    expect(inferred.reload.confidence).to eq("inferred")
  end

  it "changes nothing on a dry run, but still lists the dish" do
    samosa = create(:item, :published, name: "Samosa", ingredients: [ potato ])

    expect(run(apply: false).changes.map(&:item_id)).to eq([ samosa.id ])
    expect(samosa.reload.denormalized_ingredient_ids).not_to include(wheat.id)
  end

  it "leaves a dish alone when wheat or a wheat child is already there" do
    create(:item, :published, name: "Garlic Naan", ingredients: [ wheat_bread ])
    create(:item, :published, name: "Cheese Pizza", ingredients: [ wheat ])

    expect(run.changes).to be_empty
  end

  it "respects a gluten-free claim in the dish name" do
    create(:item, :published, name: "Gluten-Free Pizza")
    create(:item, :published, name: "Gluten-Free Country Gravy")
    expect(run.changes).to be_empty
  end

  it "ignores names that imply nothing" do
    create(:item, :published, name: "Saag Paneer")
    expect(run.changes).to be_empty
  end

  it "only touches published dishes" do
    create(:item, name: "Samosa", status: "draft")
    expect(run.changes).to be_empty
  end

  it "is idempotent" do
    create(:item, :published, name: "Samosa")
    run
    expect(run.changes).to be_empty
  end

  describe "per-rule cutoffs" do
    let(:september) { Time.utc(2026, 9, 15) }

    it "adds wheat to a pizza promoted before #638's rules went live" do
      pizza = create(:item, :published, name: "Margherita Pizza")
      expect(run.changes.map(&:item_id)).to eq([ pizza.id ])
    end

    # #638 was live, so this pizza should have wheat. It does not: a
    # person removed it, or the dish never went through the resolver
    # (added by hand). Nothing says which, so a person decides.
    it "sends a pizza promoted after #638 with no wheat to review, never writes it" do
      pizza = created_at!(create(:item, :published, name: "Margherita Pizza"), september)
      result = run
      expect(result.changes).to be_empty
      expect(result.reviews.map(&:item_id)).to eq([ pizza.id ])
      expect(pizza.reload.denormalized_ingredient_ids).not_to include(wheat.id)
    end

    it "says nothing about a gluten-free pizza promoted after #638" do
      created_at!(create(:item, :published, name: "Gluten-Free Pizza"), september)
      result = run
      expect(result.changes).to be_empty
      expect(result.reviews).to be_empty
    end

    it "still adds wheat to a samosa promoted in September, before #766" do
      samosa = created_at!(create(:item, :published, name: "Samosa"), september)
      expect(run.changes.map(&:item_id)).to eq([ samosa.id ])
    end

    # "burrito" was live in September, so this dish should have wheat
    # already, whatever "relleno" says; missing wheat goes to a person.
    it "lets the earliest rule decide when a name hits an old and a new keyword" do
      burrito = created_at!(create(:item, :published, name: "Chile Relleno Burrito"), september)
      result = run
      expect(result.changes).to be_empty
      expect(result.reviews.map(&:item_id)).to eq([ burrito.id ])
    end

    it "leaves a samosa promoted after #766 alone" do
      created_at!(create(:item, :published, name: "Samosa"), live(766) + 1.hour)
      expect(run.changes).to be_empty
    end

    it "adds wheat to a katsu promoted between #766 and #794" do
      katsu = created_at!(create(:item, :published, name: "Chicken Katsu"), live(766) + 1.minute)
      expect(run.changes.map(&:item_id)).to eq([ katsu.id ])
    end
  end

  # Nothing records a person removing an ingredient, so a dish edited
  # since a rule went live might be exactly that correction.
  it "lists a dish edited since its rule went live for review instead of writing it" do
    quesadilla = create(:item, :published, name: "Corn Quesadilla")
    quesadilla.update_columns(updated_at: Time.utc(2026, 9, 1))

    result = run

    expect(result.changes).to be_empty
    expect(result.reviews.map(&:item_id)).to eq([ quesadilla.id ])
    expect(quesadilla.reload.denormalized_ingredient_ids).not_to include(wheat.id)
  end

  describe "text-matched ingredients" do
    it "adds the matched ingredient from the name" do
      item = create(:item, :published, name: "Chicken Fried Steak with Country Gravy")
      run
      expect(item.reload.denormalized_ingredient_ids).to include(gravy.id)
      expect(item.denormalized_tag_ids).to include(gluten_tag.id)
    end

    it "adds the matched ingredient from the description" do
      item = create(:item, :published, name: "Fish Plate", description: "Breaded cod, fries.")
      run
      expect(item.reload.denormalized_ingredient_ids).to include(breading.id)
    end

    # Avoiding gravy expands down the tree, not up: a generic wheat row
    # does not hide a gravy dish from someone avoiding gravy itself.
    it "adds the specific row even when generic wheat is already there" do
      item = create(:item, :published, name: "Biscuits and Country Gravy", ingredients: [ wheat ])
      run
      expect(item.reload.denormalized_ingredient_ids).to include(gravy.id)
    end

    it "skips a match whose node is already there" do
      create(:item, :published, name: "Country Gravy", ingredients: [ gravy ])
      expect(run.changes).to be_empty
    end

    # "biscuit" was a #638 name keyword, so a September biscuit should
    # have wheat. #766's biscuit ingredient must not write it back over
    # what may be a person's removal.
    it "sends a dish whose old name rule was live and whose wheat is gone to review" do
      create(:ingredient, slug: "grain-wheat-bread-biscuit", name: "Biscuit", path: "grain.wheat.bread.biscuit")
      biscuit = created_at!(create(:item, :published, name: "Biscuit"), Time.utc(2026, 9, 15))
      result = run
      expect(result.changes).to be_empty
      expect(result.reviews.map(&:item_id)).to eq([ biscuit.id ])
      expect(biscuit.reload.denormalized_ingredient_ids).to be_empty
    end

    # Same correction, but the description names something the removal
    # did not cover. Not written over the correction, not dropped either.
    it "sends a corrected dish's description matches to review, never writes them" do
      sandwich = created_at!(create(:item, :published, name: "Chicken Sandwich",
                                                       description: "Breaded chicken, no bun."),
                             Time.utc(2026, 9, 15))

      result = run

      expect(result.changes).to be_empty
      expect(result.reviews.map(&:item_id)).to eq([ sandwich.id ])
      expect(result.reviews.first.ingredient_slugs).to include("grain-wheat-breading")
      expect(sandwich.reload.denormalized_ingredient_ids).not_to include(breading.id)
    end
  end

  # #794: an ingredient that is not a grain but almost always carries one.
  describe "gluten implications" do
    let!(:soy_sauce)    { create(:ingredient, slug: "soy-soy-sauce", name: "Soy Sauce", path: "soy.soy_sauce") }
    let!(:malt_vinegar) { create(:ingredient, slug: "condiment-malt-vinegar", name: "Malt Vinegar", path: "condiment.malt_vinegar") }

    it "adds wheat to an old dish that already carries soy sauce" do
      stir_fry = create(:item, :published, name: "Vegetable Stir Fry", ingredients: [ soy_sauce ])
      run
      expect(stir_fry.reload.denormalized_ingredient_ids).to include(wheat.id)
    end

    # A possible wheat correction must not hold back a barley row that no
    # rule ever added: each base is judged on its own.
    it "writes a new barley row even when the dish's wheat goes to review" do
      sandwich = created_at!(create(:item, :published, name: "Fish Sandwich",
                                                       description: "Malt vinegar on the side."),
                             Time.utc(2026, 9, 15))

      result = run

      expect(result.reviews.map(&:ingredient_slugs)).to eq([ [ "grain-wheat" ] ])
      expect(result.changes.map(&:ingredient_slugs)).to eq([ [ "grain-barley" ] ])
      expect(sandwich.reload.denormalized_ingredient_ids).to include(barley.id)
      expect(sandwich.denormalized_ingredient_ids).not_to include(wheat.id)
    end

    it "writes wheat and barley on one dish without tripping over the shared tag" do
      plate = create(:item, :published, name: "Fish Sandwich", description: "Malt vinegar on the side.")
      expect(run.failures).to be_empty
      expect(plate.reload.denormalized_ingredient_ids).to include(wheat.id, barley.id)
      expect(plate.item_tags.where(tag: gluten_tag).count).to eq(1)
    end

    # The base is barley here, not wheat: a dish can need barley whatever
    # happened to its wheat.
    it "adds barley for malt vinegar" do
      chips = create(:item, :published, name: "Fish and Chips", description: "Malt vinegar on the side.")
      run
      expect(chips.reload.denormalized_ingredient_ids).to include(barley.id)
    end
  end

  it "reports a failing dish and carries on with the rest" do
    bad  = create(:item, :published, name: "Samosa")
    good = create(:item, :published, name: "Chile Relleno")
    allow(ItemIngredient).to receive(:create!).and_wrap_original do |original, **attrs|
      raise ActiveRecord::RecordInvalid if attrs[:item].id == bad.id

      original.call(**attrs)
    end

    result = run

    expect(result.failures.map(&:item_id)).to eq([ bad.id ])
    expect(result.changes.map(&:item_id)).to eq([ good.id ])
    expect(bad.reload.denormalized_ingredient_ids).not_to include(wheat.id)
  end

  it "yields each change as it is made" do
    create(:item, :published, name: "Samosa")
    seen = []
    described_class.call(apply: true) { |change| seen << change.item_name }
    expect(seen).to eq([ "Samosa" ])
  end

  it "reports a dish as written even when the progress callback fails" do
    samosa = create(:item, :published, name: "Samosa")
    expect { described_class.call(apply: true) { raise IOError, "stdout closed" } }.to raise_error(IOError)
    expect(samosa.reload.denormalized_ingredient_ids).to include(wheat.id)
  end
end
