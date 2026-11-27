require "rails_helper"
require Rails.root.join("db/migrate/20261127220100_backfill_egg_compound_allergen_tags")

# Egg noodles on a dish derived gluten but not contains-egg, so an
# egg-avoider saw Khao Soi as safe. This is the live-row half of the
# SLUG_TAGS link. Drafts are included because a later status-only
# publish does not re-derive allergens.
RSpec.describe BackfillEggCompoundAllergenTags do
  let!(:egg_noodle) do
    create(:ingredient, slug: "grain-wheat-noodle-egg", name: "Egg Noodle",
                        path: "grain.wheat.noodle.egg")
  end
  let!(:wonton) do
    create(:ingredient, slug: "grain-wheat-wonton", name: "Wonton", path: "grain.wheat.wonton")
  end
  let!(:tomato) { create(:ingredient, slug: "vegetable-tomato", name: "Tomato", path: "vegetable.tomato") }
  let!(:egg_tag) do
    create(:tag, slug: "contains-egg", name: "Contains Egg", family: "allergen",
                 path: "allergen.contains_egg")
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

  it "adds suggested contains-egg to a published egg-noodle dish and unconfirms it" do
    dish = create(:item, :published, :confirmed, restaurant: restaurant, name: "Khao Soi")
    join_for(dish, egg_noodle)

    described_class.new.up

    expect(dish.item_tags.find_by!(tag: egg_tag))
      .to have_attributes(confidence: "suggested", source: "ingredient_derived")
    expect(dish.reload.read_attribute(:tag_ids)).to eq([ egg_tag.id ])
    expect(dish.confidence).to eq("suggested")
  end

  it "covers wonton wrappers too" do
    dish = create(:item, :published, restaurant: restaurant, name: "Wonton Soup")
    join_for(dish, wonton)

    described_class.new.up

    expect(dish.item_tags.find_by!(tag: egg_tag).source).to eq("ingredient_derived")
  end

  it "covers a draft dish so a later status-only publish is not missing contains-egg" do
    dish = create(:item, restaurant: restaurant, name: "Khao Soi", status: "draft")
    join_for(dish, egg_noodle)

    described_class.new.up

    expect(dish.item_tags.find_by!(tag: egg_tag))
      .to have_attributes(confidence: "suggested", source: "ingredient_derived")
    expect(dish.reload.read_attribute(:tag_ids)).to eq([ egg_tag.id ])
  end

  it "leaves a hand-added contains-egg row and a dish without the compound alone" do
    tagged = create(:item, :published, restaurant: restaurant, name: "Khao Soi")
    join_for(tagged, egg_noodle)
    ItemTag.create!(item: tagged, tag: egg_tag, confidence: "confirmed", source: "human")
    fries = create(:item, :published, restaurant: restaurant, name: "Fries")
    join_for(fries, tomato)

    described_class.new.up

    expect(tagged.item_tags.find_by!(tag: egg_tag))
      .to have_attributes(confidence: "confirmed", source: "human")
    expect(fries.item_tags).to be_empty
  end

  it "is a no-op on a second run" do
    dish = create(:item, :published, restaurant: restaurant, name: "Khao Soi")
    join_for(dish, egg_noodle)

    described_class.new.up
    expect { described_class.new.up }.not_to change { dish.item_tags.count }
  end

  it "does nothing when the taxonomy is missing" do
    dish = create(:item, :published, restaurant: restaurant, name: "Khao Soi")
    join_for(dish, egg_noodle)
    Tag.where(slug: "contains-egg").delete_all

    described_class.new.up

    expect(dish.reload.item_tags).to be_empty
  end
end
