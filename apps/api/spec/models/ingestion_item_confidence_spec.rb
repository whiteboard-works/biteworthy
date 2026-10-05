# frozen_string_literal: true

require "rails_helper"

# Confidence assignment is safety-critical: Strict mode only shows items
# where every association is "confirmed", so a pipeline that stamps everything
# "confirmed" (including AI guesses) makes Strict a no-op. This spec runs
# realistic fixtures through the full resolve → promote path and asserts the
# weakest-link confidence derivation.
RSpec.describe IngestionItem, "confidence assignment" do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) { create(:ingestion_run, restaurant: restaurant, status: "staged") }
  let(:admin) { create(:user, :admin) }
  let(:community) { create(:user) }

  let!(:wheat) { create(:ingredient, name: "Wheat", slug: "grain-wheat", path: "grain.wheat") }
  let!(:pancake) do
    create(:ingredient, name: "Pancake", slug: "grain-wheat-pancake", path: "grain.wheat.pancake")
  end
  let!(:cheese) { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }
  let!(:tomato) { create(:ingredient, name: "Tomato", slug: "vegetable-tomato", path: "vegetable.tomato") }

  # Admin accept: explicit matches → confirmed, implied bases → suggested, AI → inferred/suggested
  describe "admin accept with mixed sources" do
    it "assigns confirmed to explicit matches, suggested to derived, inferred to low-conf AI" do
      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        description: "tomato sauce, cheddar cheese",
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" },      # explicit → confirmed
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" },   # explicit → confirmed
          { slug: "grain-wheat", confidence: 0.8, source: "derived" },      # implied base → suggested
          { slug: "grain-wheat-pancake", confidence: 0.6, source: "ai" }    # low AI → inferred
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: admin)

      cheddar_join = item.item_ingredients.find_by(ingredient: cheese)
      tomato_join = item.item_ingredients.find_by(ingredient: tomato)
      wheat_join = item.item_ingredients.find_by(ingredient: wheat)
      pancake_join = item.item_ingredients.find_by(ingredient: pancake)

      expect(cheddar_join.confidence).to eq("confirmed")
      expect(cheddar_join.source).to eq("human")

      expect(tomato_join.confidence).to eq("confirmed")
      expect(tomato_join.source).to eq("human")

      expect(wheat_join.confidence).to eq("suggested")
      expect(wheat_join.source).to eq("derived")

      expect(pancake_join.confidence).to eq("inferred")
      expect(pancake_join.source).to eq("ai")

      # Item confidence = weakest link (inferred)
      expect(item.confidence).to eq("inferred")
    end

    it "derives item confidence as confirmed when all joins are confirmed" do
      ing_item = run.ingestion_items.create!(
        name: "Cheddar Cheese",
        description: "aged cheddar",
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" }
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: admin)

      expect(item.item_ingredients.count).to eq(1)
      expect(item.item_ingredients.first.confidence).to eq("confirmed")
      expect(item.confidence).to eq("confirmed")
    end

    it "derives item confidence as suggested when any join is suggested" do
      ing_item = run.ingestion_items.create!(
        name: "Pizza Margherita",
        description: "tomato, mozzarella, basil",
        ingredients_payload: [
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" },
          { slug: "grain-wheat", confidence: 0.8, source: "derived" } # implied pizza base
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: admin)

      expect(item.confidence).to eq("suggested")
    end
  end

  # Community accept: caps at "suggested" even for explicit matches
  describe "community accept confidence cap" do
    it "caps explicit matches at suggested for community scanners" do
      ing_item = run.ingestion_items.create!(
        name: "Tomato",
        description: "fresh tomato",
        ingredients_payload: [
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" }
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: community)

      tomato_join = item.item_ingredients.find_by(ingredient: tomato)
      expect(tomato_join.confidence).to eq("suggested") # capped, not confirmed
      expect(item.confidence).to eq("suggested")
    end

    it "still assigns inferred to low-conf AI for community accept" do
      ing_item = run.ingestion_items.create!(
        name: "Mystery Dish",
        ingredients_payload: [
          { slug: "grain-wheat-pancake", confidence: 0.5, source: "ai" }
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: community)

      pancake_join = item.item_ingredients.find_by(ingredient: pancake)
      expect(pancake_join.confidence).to eq("inferred")
      expect(item.confidence).to eq("inferred")
    end
  end

  # Realistic fixture: hotcake item with explicit + derived ingredients
  describe "realistic hotcake example" do
    it "marks explicit 'hotcake' match as confirmed but item as suggested due to derived wheat" do
      # "hotcake" is now an alias for grain-wheat-pancake, so it matches explicitly
      Ingredient.find_by(slug: "grain-wheat-pancake")&.update!(aliases: ["hotcake", "flapjack"])

      ing_item = run.ingestion_items.create!(
        name: "Buttermilk Hotcake",
        description: "fluffy hotcake with butter and syrup",
        ingredients_payload: [
          { slug: "grain-wheat-pancake", confidence: 0.95, source: "match" }, # alias match
          { slug: "grain-wheat", confidence: 0.8, source: "derived" }         # implied base from "pancake" keyword
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: admin)

      pancake_join = item.item_ingredients.find_by(ingredient: pancake)
      wheat_join = item.item_ingredients.find_by(ingredient: wheat)

      expect(pancake_join.confidence).to eq("confirmed") # alias match at 0.95
      expect(wheat_join.confidence).to eq("suggested")   # derived
      expect(item.confidence).to eq("suggested")         # weakest link
    end
  end

  # Update flow: append-only confidence semantics
  describe "update-accept confidence" do
    it "appends new ingredients with appropriate confidence to existing item" do
      existing_item = create(:item, :published, restaurant: restaurant,
                             name: "Cheese Plate", confidence: "confirmed")
      ItemIngredient.create!(item: existing_item, ingredient: cheese,
                             confidence: "confirmed", source: "human")

      ing_item = run.ingestion_items.create!(
        name: "Cheese Plate",
        description: "cheddar and tomato",
        matched_item_id: existing_item.id,
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" },
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" },
          { slug: "grain-wheat", confidence: 0.7, source: "ai" } # AI guess
        ],
        tags_payload: []
      )

      item = ing_item.promote!(decided_by: admin)

      # Cheddar already existed, not re-created
      expect(item.item_ingredients.where(ingredient: cheese).count).to eq(1)
      # New ingredients added
      expect(item.item_ingredients.where(ingredient: tomato).count).to eq(1)
      expect(item.item_ingredients.where(ingredient: wheat).count).to eq(1)

      wheat_join = item.item_ingredients.find_by(ingredient: wheat)
      expect(wheat_join.confidence).to eq("inferred") # low AI confidence

      # Item downgrades from confirmed to inferred due to new inferred join
      item.reload
      expect(item.confidence).to eq("inferred")
    end
  end

  # Regression: ItemIngredient validation must accept source="derived" after insert_all
  describe "ActiveRecord validation after promote with derived source" do
    it "allows updating a join row created with source=derived through ActiveRecord" do
      ing_item = run.ingestion_items.create!(
        name: "Pizza",
        description: "tomato pizza",
        ingredients_payload: [
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" },
          { slug: "grain-wheat", confidence: 0.9, source: "derived" } # implied base
        ]
      )

      item = ing_item.promote!(decided_by: admin)
      wheat_join = item.item_ingredients.find_by(ingredient: wheat)

      # The join was inserted with source="derived"
      expect(wheat_join.source).to eq("derived")
      expect(wheat_join.confidence).to eq("suggested")

      # Updating through ActiveRecord (e.g. graduating confidence) must validate
      expect { wheat_join.update!(confidence: "confirmed") }.not_to raise_error
      expect(wheat_join.reload.confidence).to eq("confirmed")
    end
  end

  # Weakest-link derivation must gather all confidences, not rely on SQL MIN (alphabetical)
  describe "mixed confidence derivation (weakest link)" do
    it "[confirmed, suggested] → suggested" do
      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" },    # confirmed
          { slug: "grain-wheat", confidence: 0.9, source: "derived" }     # suggested
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("suggested")
    end

    it "[confirmed, inferred] → inferred" do
      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" },    # confirmed
          { slug: "grain-wheat", confidence: 0.5, source: "ai" }          # inferred
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("inferred")
    end

    it "[suggested, inferred] → inferred" do
      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        ingredients_payload: [
          { slug: "grain-wheat", confidence: 0.9, source: "derived" },    # suggested
          { slug: "dairy-cheddar", confidence: 0.5, source: "ai" }        # inferred
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("inferred")
    end

    it "all confirmed → confirmed" do
      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        ingredients_payload: [
          { slug: "dairy-cheddar", confidence: 1.0, source: "match" },
          { slug: "vegetable-tomato", confidence: 1.0, source: "match" }
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("confirmed")
    end

    it "mixed ingredients and tags (suggested ingredient + confirmed tag → suggested)" do
      cuisine_tag = create(:tag, name: "Italian", slug: "cuisine-italian", path: "cuisine.italian")

      ing_item = run.ingestion_items.create!(
        name: "Cheese Pizza",
        ingredients_payload: [
          { slug: "grain-wheat", confidence: 0.9, source: "derived" }     # suggested
        ],
        tags_payload: [
          { slug: "cuisine-italian", confidence: 1.0, source: "match" }   # confirmed
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("suggested")
    end

    it "no joins at all defaults to suggested (safer than confirmed)" do
      ing_item = run.ingestion_items.create!(
        name: "Mystery Dish",
        ingredients_payload: []
      )
      item = ing_item.promote!(decided_by: admin)
      expect(item.confidence).to eq("suggested")
    end

    it "nil numeric confidence is treated as below threshold → suggested" do
      ing_item = run.ingestion_items.create!(
        name: "Pizza",
        ingredients_payload: [
          { slug: "grain-wheat", confidence: nil, source: "match" }
        ]
      )
      item = ing_item.promote!(decided_by: admin)
      # nil numeric < 0.95, so source:"match" falls through to suggested
      expect(item.confidence).to eq("suggested")
    end
  end
end
