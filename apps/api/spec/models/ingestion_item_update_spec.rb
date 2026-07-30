require "rails_helper"

# Re-scan apply semantics: promote! on a matched IngestionItem merges the
# scan into the existing Item instead of creating a duplicate, and undo!
# restores exactly what the merge changed. The invariants here are the
# safety contract for allergy users — existing confirmed data is never
# removed or downgraded by a scan, and absence of evidence never deletes.
RSpec.describe IngestionItem, "#promote! (update path)" do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, restaurant: restaurant, status: "staged") }
  let(:admin)      { create(:user, is_admin: true, password: "password123") }
  let(:scanner)    { create(:user, is_admin: false, password: "password123") }

  let!(:beef)  { create(:ingredient, slug: "meat-beef") }
  let!(:onion) { create(:ingredient, slug: "vegetable-onion") }
  let!(:grilled_tag) { create(:tag, slug: "grilled") }

  let(:target) do
    create(:item, restaurant: restaurant, name: "Carne Asada Taco",
                  description: "The original.", status: "published", confidence: "confirmed")
  end

  def staged(attrs = {})
    create(:ingestion_item, {
      ingestion_run: run, name: "Carne Asada Tacos",
      description: nil, matched_item_id: target.id, match_score: 1.0,
      ingredients_payload: [], tags_payload: [], prices_payload: []
    }.merge(attrs))
  end

  describe "linking" do
    it "links the matched Item instead of creating a new one" do
      row = staged

      expect { row.promote! }.not_to change(Item, :count)
      expect(row.reload.item).to eq(target)
      expect(row.decision).to eq("accepted")
      expect(row.applied_changes).to eq({})
    end

    it "falls back to create when the matched Item is gone" do
      row = staged
      target.destroy # FK nullifies matched_item_id
      row.reload

      expect { row.promote! }.to change(Item, :count).by(1)
      expect(row.reload.item_id).not_to be_nil
      expect(row.matched_item_id).to be_nil
    end

    it "never updates across restaurants even if matched_item_id points there" do
      foreign = create(:item, restaurant: create(:restaurant), name: "Carne Asada Taco")
      row = staged(matched_item_id: foreign.id)

      expect { row.promote! }.to change(Item, :count).by(1)
      expect(row.reload.item_id).not_to eq(foreign.id)
    end
  end

  describe "description" do
    it "overwrites when the scan carries a different description" do
      row = staged(description: "Now with lime crema.")
      row.promote!

      expect(target.reload.description).to eq("Now with lime crema.")
      expect(row.reload.applied_changes["description"]).to eq(["The original.", "Now with lime crema."])
    end

    it "never blanks a description the scan didn't carry" do
      row = staged(description: nil)
      row.promote!

      expect(target.reload.description).to eq("The original.")
    end
  end

  describe "prices" do
    before { ItemVariant.create!(item: target, size: "small", price_cents: 450, position: 0) }

    it "replaces the variant set when the scanned prices differ" do
      row = staged(prices_payload: [{ "size" => "small", "price_cents" => 550 }])
      row.promote!

      expect(target.reload.item_variants.pluck(:size, :price_cents)).to eq([["small", 550]])
      expect(row.reload.applied_changes["variants_replaced"]).to eq(
        [{ "size" => "small", "price_cents" => 450, "currency" => "USD", "position" => 0 }]
      )
    end

    it "never deletes variants when the scan carries no prices" do
      row = staged(prices_payload: [])
      row.promote!

      expect(target.reload.item_variants.pluck(:price_cents)).to eq([450])
      expect(row.reload.applied_changes).not_to have_key("variants_replaced")
    end

    it "leaves an identical price set untouched (no snapshot noise)" do
      row = staged(prices_payload: [{ "size" => "small", "price_cents" => 450 }])
      row.promote!

      expect(row.reload.applied_changes).to eq({})
    end
  end

  describe "ingredients and tags (append-only)" do
    let!(:existing_join) do
      ItemIngredient.create!(item: target, ingredient: beef,
                             confidence: "confirmed", source: "human")
    end

    it "appends new slugs and records the created join ids" do
      row = staged(ingredients_payload: [
                     { "slug" => "meat-beef", "confidence" => 0.97 },
                     { "slug" => "vegetable-onion", "confidence" => 0.93 }
                   ],
                   tags_payload: [{ "slug" => "grilled", "confidence" => 0.9 }])
      row.promote!(decided_by: admin)

      expect(target.reload.ingredients).to contain_exactly(beef, onion)
      new_join = target.item_ingredients.find_by(ingredient: onion)
      expect(new_join.confidence).to eq("confirmed")
      expect(new_join.source).to eq("human")
      expect(row.reload.applied_changes["created_item_ingredient_ids"]).to eq([new_join.id])
      expect(target.item_tags.count).to eq(1)
      # The denormalized arrays followed the joins.
      expect(target.ingredient_ids).to contain_exactly(beef.id, onion.id)
    end

    it "never removes or downgrades an existing confirmed join" do
      row = staged(ingredients_payload: [{ "slug" => "vegetable-onion", "confidence" => 0.5 }])
      row.promote!(decided_by: scanner)

      existing_join.reload
      expect(existing_join.confidence).to eq("confirmed")
      expect(target.reload.ingredients).to include(beef)
    end
  end

  describe "trust model" do
    it "admin accept appends confirmed joins and keeps the Item confirmed" do
      row = staged(ingredients_payload: [{ "slug" => "vegetable-onion", "confidence" => 0.9 }])
      row.promote!(decided_by: admin)

      expect(target.reload.confidence).to eq("confirmed")
      expect(target.item_ingredients.pluck(:confidence)).to all(eq("confirmed"))
    end

    it "community accept that adds joins downgrades a confirmed Item to suggested" do
      row = staged(ingredients_payload: [{ "slug" => "vegetable-onion", "confidence" => 0.9 }])
      row.promote!(decided_by: scanner)

      expect(target.reload.confidence).to eq("suggested")
      expect(row.reload.applied_changes["confidence"]).to eq(%w[confirmed suggested])
    end

    it "community accept with no new joins leaves the Item's confidence alone" do
      row = staged(description: "Now with lime crema.")
      row.promote!(decided_by: scanner)

      expect(target.reload.confidence).to eq("confirmed")
    end

    it "never upgrades a suggested Item (graduation belongs to confirm-all)" do
      target.update!(confidence: "suggested")
      row = staged(ingredients_payload: [{ "slug" => "vegetable-onion", "confidence" => 0.9 }])
      row.promote!(decided_by: admin)

      expect(target.reload.confidence).to eq("suggested")
    end
  end

  describe "#undo! after an update-accept" do
    it "restores description, confidence, variants, and created joins — never destroys the Item" do
      ItemVariant.create!(item: target, size: "small", price_cents: 450, position: 0)
      ItemIngredient.create!(item: target, ingredient: beef,
                             confidence: "confirmed", source: "human")
      row = staged(description: "Now with lime crema.",
                   prices_payload: [{ "size" => "small", "price_cents" => 550 }],
                   ingredients_payload: [{ "slug" => "vegetable-onion", "confidence" => 0.9 }])
      row.promote!(decided_by: scanner)

      expect { row.undo! }.not_to change(Item, :count)

      target.reload
      expect(target.description).to eq("The original.")
      expect(target.confidence).to eq("confirmed")
      expect(target.item_variants.pluck(:size, :price_cents)).to eq([["small", 450]])
      expect(target.ingredients).to contain_exactly(beef)
      expect(target.ingredient_ids).to contain_exactly(beef.id)

      row.reload
      expect(row.decision).to eq("pending")
      expect(row.item_id).to be_nil
      expect(row.applied_changes).to be_nil
      # Still an update card for the next accept.
      expect(row.matched_item_id).to eq(target.id)
    end

    it "a no-changes undo is a pure unlink" do
      row = staged
      row.promote!

      expect { row.undo! }.not_to change { target.reload.attributes }
      expect(row.reload.decision).to eq("pending")
      expect(row.item_id).to be_nil
    end

    it "still destroys the created Item when the accept was a fallback create" do
      row = staged
      target.destroy
      row.reload.promote!

      expect { row.undo! }.to change(Item, :count).by(-1)
      expect(row.reload.item_id).to be_nil
    end
  end
end
