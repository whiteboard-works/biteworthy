require "rails_helper"
require Rails.root.join("db/migrate/20261127220200_backfill_beer_ale_gluten_allergen_tags")

# Beer/ale on a live dish derived no contains-gluten, so a tag-only
# gluten avoider saw the beer as safe. This is the live-row half of the
# SUBTREE_TAGS link. Hard seltzer stays out.
RSpec.describe BackfillBeerAleGlutenAllergenTags do
  let!(:beer) { create(:ingredient, slug: "alcohol-beer", name: "Beer", path: "alcohol.beer") }
  let!(:lager) { create(:ingredient, slug: "alcohol-lager", name: "Lager", path: "alcohol.beer.lager") }
  let!(:seltzer) { create(:ingredient, slug: "alcohol-seltzer", name: "Hard Seltzer", path: "alcohol.seltzer") }
  let!(:gluten_tag) do
    create(:tag, slug: "contains-gluten", name: "Contains Gluten", family: "allergen",
                 path: "allergen.contains_gluten")
  end
  let(:restaurant) { create(:restaurant) }

  around do |example|
    was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was
  end

  def join_for(item, ingredient)
    ItemIngredient.create!(item: item, ingredient: ingredient,
                           confidence: "suggested", source: "match")
  end

  it "adds suggested contains-gluten to a beer dish and unconfirms it" do
    dish = create(:item, :published, :confirmed, restaurant: restaurant, name: "House Lager")
    join_for(dish, beer)

    described_class.new.up

    expect(dish.item_tags.find_by!(tag: gluten_tag))
      .to have_attributes(confidence: "suggested", source: "ingredient_derived")
    expect(dish.reload.read_attribute(:tag_ids)).to eq([ gluten_tag.id ])
    expect(dish.confidence).to eq("suggested")
  end

  it "covers beer-style children and drafts" do
    lager_dish = create(:item, restaurant: restaurant, name: "Draft Lager", status: "draft")
    join_for(lager_dish, lager)

    described_class.new.up

    expect(lager_dish.item_tags.find_by!(tag: gluten_tag).source).to eq("ingredient_derived")
  end

  it "leaves hard seltzer and a dish that already has contains-gluten alone" do
    seltzer_dish = create(:item, :published, restaurant: restaurant, name: "Hard Seltzer")
    join_for(seltzer_dish, seltzer)
    tagged = create(:item, :published, restaurant: restaurant, name: "IPA")
    join_for(tagged, beer)
    ItemTag.create!(item: tagged, tag: gluten_tag, confidence: "confirmed", source: "human")

    described_class.new.up

    expect(seltzer_dish.item_tags).to be_empty
    expect(tagged.item_tags.find_by!(tag: gluten_tag))
      .to have_attributes(confidence: "confirmed", source: "human")
  end

  it "is a no-op on a second run" do
    dish = create(:item, :published, restaurant: restaurant, name: "Beer")
    join_for(dish, beer)

    described_class.new.up
    expect { described_class.new.up }.not_to change { dish.item_tags.count }
  end
end
