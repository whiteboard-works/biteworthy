# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::BackfillConfidence do
  let(:admin) { create(:user, :admin) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) { create(:ingestion_run, restaurant: restaurant, user: admin, status: "staged") }
  let(:wheat) { create(:ingredient, slug: "grain-wheat", name: "Wheat", path: "grain.wheat") }
  let(:cheese) { create(:ingredient, slug: "dairy-cheddar", name: "Cheddar", path: "dairy.cheddar") }
  let(:gluten) { create(:tag, slug: "contains-gluten", name: "Contains gluten", path: "allergen.contains_gluten") }

  def accepted_item(name:, ingredients_payload:, tags_payload: [], join_source: "human", join_confidence: "confirmed")
    item = create(:item, :published, restaurant: restaurant, name: name, confidence: "confirmed")
    ItemIngredient.create!(item: item, ingredient: cheese, source: join_source, confidence: join_confidence)
    staged = run.ingestion_items.create!(
      name: name,
      decision: "accepted",
      item: item,
      decided_at: Time.current,
      ingredients_payload: ingredients_payload,
      tags_payload: tags_payload
    )
    [ item, staged ]
  end

  it "defaults callers to dry_run and does not write" do
    item, = accepted_item(
      name: "Pancakes",
      ingredients_payload: [
        { "slug" => "dairy-cheddar", "confidence" => 0.5, "source" => "ai" }
      ]
    )

    result = described_class.call(restaurant: restaurant)
    expect(result[:dry_run]).to be true
    expect(item.reload.item_ingredients.sole.source).to eq("human")
    expect(item.confidence).to eq("confirmed")
    expect(result[:items].first[:old_confidence]).to eq("confirmed")
    expect(result[:items].first[:new_confidence]).to eq("inferred")
  end

  it "lowers AI guesses that were stored as human/confirmed and is idempotent" do
    item, = accepted_item(
      name: "Pancakes",
      ingredients_payload: [
        { "slug" => "dairy-cheddar", "confidence" => 0.5, "source" => "ai" }
      ]
    )

    described_class.call(restaurant: restaurant, dry_run: false)
    join = item.reload.item_ingredients.sole
    expect(join.source).to eq("ai")
    expect(join.confidence).to eq("inferred")
    expect(item.confidence).to eq("inferred")

    second = described_class.call(restaurant: restaurant, dry_run: false)
    expect(second[:items]).to be_empty
    expect(item.reload.confidence).to eq("inferred")
  end

  it "reports the pre-update source and confidence in apply mode" do
    accepted_item(
      name: "Pancakes",
      ingredients_payload: [
        { "slug" => "dairy-cheddar", "confidence" => 0.5, "source" => "ai" }
      ]
    )

    result = described_class.call(restaurant: restaurant, dry_run: false)
    expect(result[:dry_run]).to be false

    change = result[:items].first[:changes].find { |row| row[:type] == :updated }
    expect(change).to include(
      slug: "dairy-cheddar",
      old_source: "human",
      old_confidence: "confirmed",
      new_source: "ai",
      new_confidence: "inferred"
    )
  end

  it "adds missing wheat/gluten rows and never raises confidence" do
    item, = accepted_item(
      name: "Pizza",
      ingredients_payload: [
        { "slug" => "dairy-cheddar", "confidence" => 1.0, "source" => "match" },
        { "slug" => "grain-wheat", "confidence" => 0.8, "source" => "derived" }
      ],
      tags_payload: [
        { "slug" => "contains-gluten", "confidence" => 0.8, "source" => "ingredient_derived", "from_source" => "derived" }
      ]
    )
    wheat
    gluten
    item.update!(confidence: "inferred")

    result = described_class.call(restaurant: restaurant, dry_run: false)
    expect(item.item_ingredients.find_by(ingredient: wheat).source).to eq("derived")
    expect(item.item_ingredients.find_by(ingredient: wheat).confidence).to eq("suggested")
    expect(item.item_tags.find_by(tag: gluten).source).to eq("ingredient_derived")
    expect(result[:items].first[:allergen_rows_added]).to include("grain-wheat", "contains-gluten")
    expect(item.reload.confidence).to eq("inferred")
  end
end
