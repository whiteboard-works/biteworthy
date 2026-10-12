require "rails_helper"

# Dishes promoted before #907 carry a compound sauce (aioli, hollandaise,
# pesto) with no row for the allergen it is made from, so an avoider
# still sees them as safe. The backfill adds those rows, add-only.
RSpec.describe Menus::SauceAllergenBackfill do
  include ActiveSupport::Testing::TimeHelpers

  let!(:aioli)      { create(:ingredient, slug: "condiment-aioli", name: "Aioli", path: "condiment.aioli") }
  let!(:pesto)      { create(:ingredient, slug: "condiment-pesto", name: "Pesto", path: "condiment.pesto") }
  let!(:egg)        { create(:ingredient, slug: "egg", name: "Egg", path: "egg") }
  let!(:parmesan)   { create(:ingredient, slug: "dairy-parmesan", name: "Parmesan", path: "dairy.parmesan") }
  let!(:pine_nuts)  { create(:ingredient, slug: "tree_nut-pine-nuts", name: "Pine nuts", path: "tree_nut.pine_nuts") }
  let!(:egg_tag)    { create(:tag, slug: "contains-egg", name: "Contains Egg", family: "allergen") }

  around { |ex| travel_to(described_class::LIVE_SINCE - 1.day) { ex.run } }

  def run(apply: true) = described_class.call(apply: apply)

  it "adds a derived, suggested egg row and tag to a dish with aioli, and lowers a confirmed dish" do
    calamari = create(:item, :published, :confirmed, name: "Calamari", ingredients: [ aioli ])

    result = run

    expect(result.changes.map(&:item_id)).to eq([ calamari.id ])
    expect(calamari.item_ingredients.find_by!(ingredient: egg))
      .to have_attributes(source: "derived", confidence: "suggested")
    expect(calamari.item_tags.find_by!(tag: egg_tag))
      .to have_attributes(source: "ingredient_derived", confidence: "suggested")
    calamari.reload
    # The filter reads the denormalized arrays; this is what hides it.
    expect(calamari.denormalized_ingredient_ids).to include(egg.id)
    expect(calamari.confidence).to eq("suggested")
  end

  it "keeps a name's vegan claim: pine nuts yes, parmesan no" do
    dish = create(:item, :published, name: "Vegan Pesto Pasta", ingredients: [ pesto ])

    run

    expect(dish.reload.denormalized_ingredient_ids).to include(pine_nuts.id)
    expect(dish.denormalized_ingredient_ids).not_to include(parmesan.id)
  end

  it "adds nothing a dish already carries, and is idempotent" do
    create(:item, :published, name: "Pesto Pasta", ingredients: [ pesto, parmesan, pine_nuts ])
    create(:item, :published, name: "Calamari", ingredients: [ aioli ])

    expect(run.changes.size).to eq(1)
    expect(run.changes).to be_empty
  end

  it "writes nothing on a dry run" do
    dish = create(:item, :published, name: "Calamari", ingredients: [ aioli ])

    expect(run(apply: false).changes.size).to eq(1)
    expect(dish.reload.denormalized_ingredient_ids).not_to include(egg.id)
  end

  it "leaves dishes promoted after the rule went live alone" do
    dish = create(:item, :published, name: "Calamari", ingredients: [ aioli ])
    dish.update_columns(created_at: described_class::LIVE_SINCE + 1.hour)

    expect(run.changes).to be_empty
  end
end
