require "rails_helper"

# Dishes published before the implied-base table grew (#638, #766) never
# got the wheat their names imply, so a Celiac filter still shows them.
# The backfill applies today's table to them. It must only ever add: a
# wrong wheat row hides a dish with a reason a person can fix, while a
# missing one fails silently, which is the failure this exists to stop.
RSpec.describe Menus::ImpliedBaseBackfill do
  include ActiveSupport::Testing::TimeHelpers

  let!(:wheat)       { create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat") }
  let!(:wheat_bread) { create(:ingredient, slug: "grain-wheat-bread", name: "Bread", path: "grain.wheat.bread") }
  let!(:potato)      { create(:ingredient, slug: "veg-potato", name: "Potato", path: "veg.potato") }
  let!(:gluten_tag)  { create(:tag, slug: "contains-gluten", name: "Contains Gluten", family: "allergen") }

  # Every dish here predates both keyword tables unless a test says otherwise.
  around { |ex| travel_to(described_class::LIVE_SINCE_638 - 1.day) { ex.run } }

  def created_at!(item, time) = item.tap { |i| i.update_columns(created_at: time) }

  def run(apply: true) = described_class.call(apply: apply)

  it "adds a derived, suggested wheat row and the gluten tag to a samosa" do
    samosa = create(:item, :published, :confirmed, name: "Vegetable Samosa", ingredients: [ potato ])

    result = run

    expect(result.changes.map(&:item_id)).to eq([ samosa.id ])
    expect(samosa.item_ingredients.find_by!(ingredient: wheat))
      .to have_attributes(source: "derived", confidence: "suggested")
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
    expect(run.changes).to be_empty
  end

  it "ignores names that imply no base" do
    create(:item, :published, name: "Saag Paneer")
    expect(run.changes).to be_empty
  end

  it "only touches published dishes" do
    create(:item, name: "Samosa", status: "draft")
    expect(run.changes).to be_empty
  end

  # A dish promoted after its keyword went live already went through
  # it, so missing wheat there means a person removed it. A rerun must
  # not undo that.
  describe "per-keyword cutoffs" do
    let(:september) { Time.utc(2026, 9, 15) }

    it "adds wheat to a pizza promoted before #638's table went live" do
      pizza = create(:item, :published, name: "Margherita Pizza")
      expect(run.changes.map(&:item_id)).to eq([ pizza.id ])
    end

    it "leaves a pizza promoted after #638 alone (a person removed its wheat)" do
      created_at!(create(:item, :published, name: "Margherita Pizza"), september)
      expect(run.changes).to be_empty
    end

    it "still adds wheat to a samosa promoted in September, before #766 went live" do
      samosa = created_at!(create(:item, :published, name: "Samosa"), september)
      expect(run.changes.map(&:item_id)).to eq([ samosa.id ])
    end

    # "burrito" was live in September, so this dish got wheat then;
    # missing wheat now is a correction, whatever "relleno" says.
    it "uses the earliest keyword when a name hits an old and a new one" do
      created_at!(create(:item, :published, name: "Chile Relleno Burrito"), september)
      expect(run.changes).to be_empty
      expect(run.reviews).to be_empty
    end

    it "leaves a samosa promoted after #766 alone" do
      created_at!(create(:item, :published, name: "Samosa"), described_class::LIVE_SINCE_766 + 1.hour)
      expect(run.changes).to be_empty
    end
  end

  # Nothing records a person removing an ingredient, so a dish edited
  # since its keyword went live might be exactly that correction.
  it "lists a dish edited since its keyword went live for review instead of writing it" do
    pizza = create(:item, :published, name: "Corn Quesadilla")
    pizza.update_columns(updated_at: Time.utc(2026, 9, 1))

    result = run

    expect(result.changes).to be_empty
    expect(result.reviews.map(&:item_id)).to eq([ pizza.id ])
    expect(pizza.reload.denormalized_ingredient_ids).not_to include(wheat.id)
  end

  # #766 also added wheat ingredients that scans match from the dish
  # text, not the name table. Old dishes never met them.
  describe "#766's text-matched wheat ingredients" do
    let!(:gravy) do
      create(:ingredient, slug: "grain-wheat-gravy", name: "Wheat-Based Gravy",
                          path: "grain.wheat.gravy", aliases: [ "country gravy" ])
    end
    let!(:breading) do
      create(:ingredient, slug: "grain-wheat-breading", name: "Breading",
                          path: "grain.wheat.breading", aliases: [ "breaded" ])
    end

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

    it "skips a dish that already has wheat" do
      create(:item, :published, name: "Country Gravy", ingredients: [ wheat ])
      expect(run.changes).to be_empty
    end

    it "respects a gluten-free claim in the name" do
      create(:item, :published, name: "Gluten-Free Country Gravy")
      expect(run.changes).to be_empty
    end

    it "leaves a dish promoted after #766 alone" do
      created_at!(create(:item, :published, name: "Country Gravy"), described_class::LIVE_SINCE_766 + 1.hour)
      expect(run.changes).to be_empty
    end
  end

  it "reports a dish as written even when the progress callback fails" do
    samosa = create(:item, :published, name: "Samosa")
    expect { described_class.call(apply: true) { raise IOError, "stdout closed" } }.to raise_error(IOError)
    expect(samosa.reload.denormalized_ingredient_ids).to include(wheat.id)
  end

  it "is idempotent" do
    create(:item, :published, name: "Samosa")
    run
    expect(run.changes).to be_empty
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
end
