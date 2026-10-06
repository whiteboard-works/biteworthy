require "rails_helper"

# Dishes published before the implied-base table grew (#638, #766) never
# got the wheat their names imply, so a Celiac filter still shows them.
# The backfill applies today's table to them. It must only ever add: a
# wrong wheat row hides a dish with a reason a person can fix, while a
# missing one fails silently, which is the failure this exists to stop.
RSpec.describe Menus::ImpliedBaseBackfill do
  let!(:wheat)       { create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat") }
  let!(:wheat_bread) { create(:ingredient, slug: "grain-wheat-bread", name: "Bread", path: "grain.wheat.bread") }
  let!(:potato)      { create(:ingredient, slug: "veg-potato", name: "Potato", path: "veg.potato") }

  def wheat_ids(item) = item.reload.denormalized_ingredient_ids

  it "adds a derived, suggested wheat row to a samosa that has none" do
    samosa = create(:item, :published, :confirmed, name: "Vegetable Samosa", ingredients: [ potato ])

    changes = described_class.call(apply: true)

    expect(changes.map(&:item_id)).to eq([ samosa.id ])
    row = samosa.item_ingredients.find_by!(ingredient: wheat)
    expect(row).to have_attributes(source: "derived", confidence: "suggested")
    # The filter reads the denormalized array; this is what hides it.
    expect(wheat_ids(samosa)).to include(wheat.id)
  end

  # Item confidence is the weakest link. A confirmed dish with a
  # suggested row is no longer confirmed, so Strict mode hides it too.
  it "lowers a confirmed dish to suggested" do
    samosa = create(:item, :published, :confirmed, name: "Samosa", ingredients: [ potato ])
    described_class.call(apply: true)
    expect(samosa.reload.confidence).to eq("suggested")
  end

  it "never raises an inferred dish's confidence" do
    samosa = create(:item, :published, name: "Samosa", confidence: "inferred")
    described_class.call(apply: true)
    expect(samosa.reload.confidence).to eq("inferred")
  end

  it "changes nothing on a dry run" do
    samosa = create(:item, :published, name: "Samosa", ingredients: [ potato ])

    changes = described_class.call(apply: false)

    expect(changes.map(&:item_id)).to eq([ samosa.id ])
    expect(wheat_ids(samosa)).not_to include(wheat.id)
  end

  it "leaves a dish alone when wheat or a wheat child is already there" do
    create(:item, :published, name: "Garlic Naan", ingredients: [ wheat_bread ])
    create(:item, :published, name: "Cheese Pizza", ingredients: [ wheat ])

    expect(described_class.call(apply: true)).to be_empty
  end

  it "respects a gluten-free claim in the dish name" do
    create(:item, :published, name: "Gluten-Free Pizza")
    expect(described_class.call(apply: true)).to be_empty
  end

  it "ignores names that imply no base" do
    create(:item, :published, name: "Saag Paneer")
    expect(described_class.call(apply: true)).to be_empty
  end

  it "is idempotent" do
    create(:item, :published, name: "Samosa")
    described_class.call(apply: true)
    expect(described_class.call(apply: true)).to be_empty
  end
end
