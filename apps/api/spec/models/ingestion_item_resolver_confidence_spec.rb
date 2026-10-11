# frozen_string_literal: true

require "rails_helper"

# The existing "all confirmed gives confirmed" example only passes because
# tags_payload is empty. Real resolver output always includes contains-*
# tags; this spec runs the actual DeterministicResolver so those tags
# cannot be ignored.
RSpec.describe IngestionItem, "confidence from real resolver output" do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) { create(:ingestion_run, restaurant: restaurant, status: "staged") }
  let(:admin) { create(:user, :admin) }

  let(:matcher) do
    Ingestion::IngredientMatcher.new([
      [ "dairy-mozzarella", "Mozzarella", "dairy.mozzarella", [] ],
      [ "herb-basil", "Basil", "herb.basil", [] ],
      [ "grain-wheat", "Wheat", "grain.wheat", [] ]
    ])
  end

  before do
    create(:ingredient, slug: "dairy-mozzarella", name: "Mozzarella", path: "dairy.mozzarella")
    create(:ingredient, slug: "herb-basil", name: "Basil", path: "herb.basil")
    create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat")
    create(:tag, slug: "contains-dairy", name: "Contains dairy", path: "allergen.contains_dairy")
    create(:tag, slug: "contains-gluten", name: "Contains gluten", path: "allergen.contains_gluten")
  end

  def resolve(name, description)
    Ingestion::DeterministicResolver.call(
      [ Struct.new(:id, :name, :description, :section_name).new("id-1", name, description, nil) ],
      matcher: matcher
    ).first
  end

  it "keeps keyword-to-wheat inference as derived/suggested" do
    result = resolve("Margherita Pizza", "mozzarella, basil")

    expect(result.ingredients).to include(
      { "slug" => "grain-wheat", "confidence" => 0.8, "source" => "derived" }
    )
    expect(result.tags).to include(hash_including("slug" => "contains-gluten", "source" => "ingredient_derived"))

    staged = run.ingestion_items.create!(
      name: "Margherita Pizza",
      description: "mozzarella, basil",
      ingredients_payload: result.ingredients,
      tags_payload: result.tags
    )
    item = staged.promote!(decided_by: admin)

    wheat = item.item_ingredients.joins(:ingredient).find_by(ingredients: { slug: "grain-wheat" })
    expect(wheat.source).to eq("derived")
    expect(wheat.confidence).to eq("suggested")

    gluten = item.item_tags.joins(:tag).find_by(tags: { slug: "contains-gluten" })
    expect(gluten.source).to eq("ingredient_derived")
    expect(gluten.confidence).to eq("suggested")

    expect(item.confidence).to eq("suggested")
  end

  it "stays confirmed when every ingredient is a menu-text match, even with contains-* tags" do
    result = resolve("Caprese", "mozzarella, basil")

    expect(result.ingredients.map { |r| r["source"] }).to all(eq("match"))
    expect(result.tags).to include(hash_including("slug" => "contains-dairy", "source" => "ingredient_derived"))

    staged = run.ingestion_items.create!(
      name: "Caprese",
      description: "mozzarella, basil",
      ingredients_payload: result.ingredients,
      tags_payload: result.tags
    )
    item = staged.promote!(decided_by: admin)

    expect(item.item_ingredients).to be_present
    expect(item.item_ingredients.map(&:confidence)).to all(eq("confirmed"))
    dairy = item.item_tags.joins(:tag).find_by(tags: { slug: "contains-dairy" })
    expect(dairy.source).to eq("ingredient_derived")
    expect(dairy.confidence).to eq("confirmed")
    expect(item.confidence).to eq("confirmed")
  end

  it "stays suggested when a dish has zero ingredient rows, even with a confirmed tag" do
    staged = run.ingestion_items.create!(
      name: "House Water",
      ingredients_payload: [],
      tags_payload: [ { "slug" => "contains-dairy", "confidence" => 1.0, "source" => "match" } ]
    )
    item = staged.promote!(decided_by: admin)

    expect(item.item_ingredients).to be_empty
    expect(item.item_tags).to be_present
    expect(item.confidence).to eq("suggested")
  end
end
