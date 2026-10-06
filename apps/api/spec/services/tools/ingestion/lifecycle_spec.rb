require "rails_helper"

# The scan → review → accept path, exercised through the tools rather than
# the services beneath them. What matters here is that nothing reaches a live
# menu except through accept, that a caller can only touch their own scan,
# and that accept is reversible.
RSpec.describe "ingestion tools", type: :service do
  let(:owner)      { create(:user) }
  let(:stranger)   { create(:user) }
  let(:admin)      { create(:user, is_admin: true) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, :staged, user: owner, restaurant: restaurant) }

  let!(:beef) { create(:ingredient, name: "Beef", slug: "meat-beef", path: "meat.beef") }

  def ctx(user) = { user_id: user&.id }
  def payload(response) = response.to_h[:structuredContent]

  describe "run scoping" do
    let!(:item) { create(:ingestion_item, ingestion_run: run) }

    # NotFound rather than Forbidden on purpose — "you may not touch scan X"
    # confirms scan X exists.
    it "hides another user's scan behind not_found, not forbidden" do
      response = Tools::Ingestion::GetScanStatus.call(scan_id: run.id, server_context: ctx(stranger))

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:error]).to eq("not_found")
    end

    it "lets the owner read their own scan" do
      response = Tools::Ingestion::GetScanStatus.call(scan_id: run.id, server_context: ctx(owner))

      expect(payload(response)[:ready]).to be(true)
      expect(payload(response)[:dish_count]).to eq(1)
    end

    it "lets an admin read anyone's scan" do
      response = Tools::Ingestion::GetScanStatus.call(scan_id: run.id, server_context: ctx(admin))

      expect(response.to_h[:isError]).to be_falsey
    end

    it "refuses an anonymous caller" do
      response = Tools::Ingestion::GetScanStatus.call(scan_id: run.id, server_context: {})

      expect(payload(response)[:error]).to eq("unauthorized")
    end
  end

  describe "list_staged_items" do
    let!(:item) { create(:ingestion_item, ingestion_run: run, name: "Carne Asada Taco") }

    it "fences dish text that came from a photo or scraped page" do
      response = Tools::Ingestion::ListStagedItems.call(scan_id: run.id, server_context: ctx(owner))

      expect(payload(response)[:dishes].first[:name]).to eq("<untrusted-content>Carne Asada Taco</untrusted-content>")
    end

    # confidence/source are how a verifier decides whether to trust a row.
    it "keeps confidence and source on every association" do
      dish = payload(Tools::Ingestion::ListStagedItems.call(scan_id: run.id, server_context: ctx(owner)))[:dishes].first

      expect(dish[:ingredients].first).to include(slug: "meat-beef", confidence: 1.0)
    end

    it "tells the caller to wait while the scan is still running" do
      running = create(:ingestion_run, :extracting, user: owner, restaurant: restaurant)

      response = Tools::Ingestion::ListStagedItems.call(scan_id: running.id, server_context: ctx(owner))

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/get_scan_status/)
    end

    it "surfaces only dishes worth a human look under needs_attention" do
      create(:ingestion_item, ingestion_run: run, name: "Mystery Plate", ingredients_payload: [])

      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, needs_attention: true, server_context: ctx(owner)
      )

      names = payload(response)[:dishes].map { |d| d[:name] }
      expect(names).to include(a_string_matching(/Mystery Plate/))
      expect(names).not_to include(a_string_matching(/Carne Asada/))
    end

    # The filter has to run before the limit. Selecting out of an already
    # limited page meant a big scan could answer "nothing needs attention"
    # while the unresolved dishes sat past the cut — the exact opposite of
    # what the flag promises, on the dishes the filter can't hide.
    it "finds a dish needing attention past the page the limit would cut" do
      create(:ingestion_item, ingestion_run: run, name: "Mystery Plate",
                              position: 500, ingredients_payload: [])

      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, needs_attention: true, limit: 1, server_context: ctx(owner)
      )

      expect(payload(response)[:dishes].map { |d| d[:name] })
        .to contain_exactly(a_string_matching(/Mystery Plate/))
      expect(payload(response)[:total_dishes]).to eq(1)
    end

    it "counts unresolved text as needing attention even when ingredients resolved" do
      create(:ingestion_item, ingestion_run: run, name: "Secret Sauce Bowl",
                              unresolved_ingredients: ["secret sauce"])

      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, needs_attention: true, server_context: ctx(owner)
      )

      expect(payload(response)[:dishes].map { |d| d[:name] })
        .to contain_exactly(a_string_matching(/Secret Sauce Bowl/))
    end

    it "supports offset pagination" do
      20.times { |i| create(:ingestion_item, ingestion_run: run, name: "Item #{i}", position: i) }

      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, limit: 5, offset: 10, server_context: ctx(owner)
      )

      result = payload(response)
      expect(result[:returned]).to eq(5)
      expect(result[:total_dishes]).to eq(21) # 20 + original item
      expect(result[:offset]).to eq(10)
      expect(result[:has_more]).to be(true)
    end

    it "indicates when no more items remain" do
      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, limit: 50, offset: 0, server_context: ctx(owner)
      )

      result = payload(response)
      expect(result[:has_more]).to be(false)
    end

    it "accepts up to 500 items per page" do
      response = Tools::Ingestion::ListStagedItems.call(
        scan_id: run.id, limit: 500, server_context: ctx(owner)
      )

      expect(response.to_h[:isError]).to be_falsey
      expect(payload(response)[:limit]).to eq(500)
    end
  end

  describe "edit_staged_item" do
    let!(:item) { create(:ingestion_item, ingestion_run: run) }

    it "replaces the ingredient list with human-sourced rows" do
      Tools::Ingestion::EditStagedItem.call(
        item_id: item.id, ingredient_slugs: ["meat-beef"], server_context: ctx(owner)
      )

      expect(item.reload.ingredients_payload)
        .to eq([{ "slug" => "meat-beef", "confidence" => 1.0, "source" => "human" }])
      expect(item.decision).to eq("edited")
    end

    # An unresolved ingredient is one the dietary filter cannot hide, so
    # answering it is the whole point of the edit.
    it "clears the unresolved list once a human has spoken to it" do
      item.update!(unresolved_ingredients: ["secret sauce"])

      Tools::Ingestion::EditStagedItem.call(
        item_id: item.id, ingredient_slugs: ["meat-beef"], server_context: ctx(owner)
      )

      expect(item.reload.unresolved_ingredients).to eq([])
    end

    it "rejects an unknown slug without saving anything" do
      before = item.ingredients_payload

      response = Tools::Ingestion::EditStagedItem.call(
        item_id: item.id, ingredient_slugs: %w[meat-beef not-a-thing], server_context: ctx(owner)
      )

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/search_taxonomy/)
      expect(item.reload.ingredients_payload).to eq(before)
    end

    it "refuses to edit a dish that is already on the live menu" do
      item.promote!(decided_by: admin)

      response = Tools::Ingestion::EditStagedItem.call(
        item_id: item.id, name: "Too late", server_context: ctx(owner)
      )

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/undo_staged_item/)
    end
  end

  describe "accept_staged_items" do
    let!(:item) { create(:ingestion_item, ingestion_run: run, name: "Carne Asada Taco") }

    it "creates a real menu item carrying the resolved ingredients" do
      expect {
        Tools::Ingestion::AcceptStagedItems.call(
          scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
        )
      }.to change(Item, :count).by(1)

      created = item.reload.item
      expect(created.name).to eq("Carne Asada Taco")
      expect(created.denormalized_ingredient_ids).to include(beef.id)
    end

    # The trust model: who verified decides whether strict-mode users see it.
    it "records a community accept as suggested, not confirmed" do
      Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
      )

      expect(item.reload.item.confidence).to eq("suggested")
    end

    it "records an admin accept as confirmed" do
      Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(admin)
      )

      expect(item.reload.item.confidence).to eq("confirmed")
    end

    it "accepts every pending dish under all: true" do
      create(:ingestion_item, ingestion_run: run, name: "Pollo Burrito")

      expect {
        Tools::Ingestion::AcceptStagedItems.call(scan_id: run.id, all: true, server_context: ctx(owner))
      }.to change(Item, :count).by(2)
    end

    it "accepts pending and edited dishes under all: true" do
      pending_item = create(:ingestion_item, ingestion_run: run, name: "Pollo Burrito", decision: "pending")
      edited_item = create(:ingestion_item, ingestion_run: run, name: "Veggie Bowl", decision: "edited")

      expect {
        Tools::Ingestion::AcceptStagedItems.call(scan_id: run.id, all: true, server_context: ctx(owner))
      }.to change(Item, :count).by(3)

      expect(pending_item.reload.item).to be_present
      expect(edited_item.reload.item).to be_present
    end

    it "does not accept rejected dishes with all: true" do
      rejected_item = create(:ingestion_item, ingestion_run: run, name: "Rejected Taco", decision: "rejected")

      Tools::Ingestion::AcceptStagedItems.call(scan_id: run.id, all: true, server_context: ctx(owner))

      expect(rejected_item.reload.item).to be_nil
    end

    it "returns remaining_pending count including edited dishes" do
      create(:ingestion_item, ingestion_run: run, name: "Pending Burrito", decision: "pending")
      create(:ingestion_item, ingestion_run: run, name: "Edited Bowl", decision: "edited")

      response = Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
      )

      # Should count 1 pending + 1 edited = 2 remaining
      expect(payload(response)[:remaining_pending]).to eq(2)
    end

    it "names the ids it could not find rather than silently accepting the rest" do
      response = Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id, SecureRandom.uuid], server_context: ctx(owner)
      )

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:error]).to eq("not_found")
    end

    it "refuses a bare call with neither ids nor all" do
      response = Tools::Ingestion::AcceptStagedItems.call(scan_id: run.id, server_context: ctx(owner))

      expect(response.to_h[:isError]).to be(true)
    end

    # A re-scan matched to a live dish must edit it, not duplicate it.
    context "when the dish matches one already on the menu" do
      let!(:existing) { create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco") }

      before { item.update!(matched_item_id: existing.id, match_score: 1.0, description: "Now with lime.") }

      it "updates the existing dish instead of creating a second one" do
        expect {
          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )
        }.not_to change(Item, :count)

        expect(existing.reload.description).to eq("Now with lime.")
      end

      it "tells the caller it updated rather than created" do
        response = Tools::Ingestion::AcceptStagedItems.call(
          scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
        )

        expect(payload(response)[:accepted].first[:updated_existing]).to be(true)
      end

      context "when the staged item was explicitly edited" do
        let!(:cilantro) { create(:ingredient, name: "Cilantro", slug: "herb-cilantro", path: "herb.cilantro") }
        let!(:lime) { create(:ingredient, name: "Lime", slug: "fruit-lime", path: "fruit.lime") }
        let!(:old_ingredient) { create(:ingredient, name: "Pepper", slug: "herb-pepper", path: "herb.pepper") }

        before do
          # Existing item has old ingredients
          ItemIngredient.create!(item: existing, ingredient: beef,
                                 confidence: "confirmed", source: "human")
          ItemIngredient.create!(item: existing, ingredient: old_ingredient,
                                 confidence: "confirmed", source: "human")

          # Edit the staged item with new ingredients
          item.update!(
            decision: "edited",
            name: "Baja Style Fish Tacos",
            ingredients_payload: [
              { "slug" => "herb-cilantro", "confidence" => 1.0, "source" => "human" },
              { "slug" => "fruit-lime", "confidence" => 1.0, "source" => "human" }
            ]
          )
        end

        it "applies the edited name to the existing item" do
          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )

          expect(existing.reload.name).to eq("Baja Style Fish Tacos")
        end

        it "replaces ingredients instead of merging them" do
          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )

          existing.reload
          expect(existing.denormalized_ingredient_ids).to contain_exactly(cilantro.id, lime.id)
          expect(existing.denormalized_ingredient_ids).not_to include(beef.id, old_ingredient.id)
        end

        it "derives allergen tags from the new ingredients" do
          # Create allergen-bearing ingredient
          create(:ingredient, name: "Shrimp", slug: "shellfish-shrimp", path: "shellfish.shrimp")
          shellfish_tag = create(:tag, name: "Contains shellfish", slug: "contains-shellfish",
                                 family: "allergen", path: "allergen.contains_shellfish")

          item.update!(
            ingredients_payload: [
              { "slug" => "shellfish-shrimp", "confidence" => 1.0, "source" => "human" }
            ]
          )

          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(admin)
          )

          existing.reload
          expect(existing.denormalized_tag_ids).to include(shellfish_tag.id)
          allergen_join = existing.item_tags.find_by(tag: shellfish_tag)
          expect(allergen_join.source).to eq("ingredient_derived")
          # Human-edited parent + admin accept → the allergen inherits confirmed.
          expect(allergen_join.confidence).to eq("confirmed")
        end

        it "keeps keyword-to-wheat replacement rows derived/suggested on admin accept" do
          wheat = create(:ingredient, name: "Wheat", slug: "grain-wheat", path: "grain.wheat")
          gluten = create(:tag, name: "Contains gluten", slug: "contains-gluten",
                          family: "allergen", path: "allergen.contains_gluten")

          item.update!(
            ingredients_payload: [
              { "slug" => "grain-wheat", "confidence" => 0.8, "source" => "derived" }
            ]
          )

          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(admin)
          )

          wheat_join = existing.reload.item_ingredients.find_by(ingredient: wheat)
          expect(wheat_join.source).to eq("derived")
          expect(wheat_join.confidence).to eq("suggested")
          gluten_join = existing.item_tags.find_by(tag: gluten)
          expect(gluten_join.source).to eq("ingredient_derived")
          expect(gluten_join.confidence).to eq("suggested")
          expect(existing.confidence).to eq("suggested")
        end

        it "maps derived and AI replacement rows through map_confidence" do
          item.update!(
            ingredients_payload: [
              { "slug" => "herb-cilantro", "confidence" => 1.0, "source" => "derived" },
              { "slug" => "fruit-lime", "confidence" => 0.5, "source" => "ai" }
            ]
          )

          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(admin)
          )

          existing.reload
          cilantro_join = existing.item_ingredients.find_by(ingredient: cilantro)
          lime_join = existing.item_ingredients.find_by(ingredient: lime)
          expect(cilantro_join.source).to eq("derived")
          expect(cilantro_join.confidence).to eq("suggested")
          expect(lime_join.source).to eq("ai")
          expect(lime_join.confidence).to eq("inferred")
        end

        it "can be undone to restore the original name and ingredients" do
          existing.reload
          original_name = existing.name
          original_ingredient_ids = existing.denormalized_ingredient_ids
          expect(original_ingredient_ids).to contain_exactly(beef.id, old_ingredient.id)

          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )

          expect(existing.reload.name).not_to eq(original_name)

          # Undo
          item.undo!

          expect(existing.reload.name).to eq(original_name)
          expect(existing.denormalized_ingredient_ids).to match_array(original_ingredient_ids)
        end
      end

      context "when the staged item was auto-scanned (not edited)" do
        let!(:cilantro) { create(:ingredient, name: "Cilantro", slug: "herb-cilantro", path: "herb.cilantro") }

        before do
          # Existing item has beef
          ItemIngredient.create!(item: existing, ingredient: beef,
                                 confidence: "confirmed", source: "human")

          # Auto-scanned item (decision: pending) adds cilantro
          item.update!(
            decision: "pending",
            name: "Different Name",
            ingredients_payload: [
              { "slug" => "herb-cilantro", "confidence" => 1.0, "source" => "ai" }
            ]
          )
        end

        it "does not change the name" do
          original_name = existing.name

          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )

          expect(existing.reload.name).to eq(original_name)
        end

        it "appends ingredients instead of replacing them" do
          Tools::Ingestion::AcceptStagedItems.call(
            scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
          )

          existing.reload
          expect(existing.denormalized_ingredient_ids).to include(beef.id, cilantro.id)
        end
      end
    end
  end

  describe "reject_staged_items" do
    let!(:item) { create(:ingestion_item, ingestion_run: run) }

    it "marks the dish rejected without touching the live menu" do
      expect {
        Tools::Ingestion::RejectStagedItems.call(
          scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
        )
      }.not_to change(Item, :count)

      expect(item.reload.decision).to eq("rejected")
    end

    # Rejecting the staged row of a published dish would leave the Item
    # behind with the record claiming it was never accepted.
    it "refuses a dish that is already on the live menu" do
      item.promote!(decided_by: admin)

      response = Tools::Ingestion::RejectStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
      )

      expect(response.to_h[:isError]).to be(true)
      expect(payload(response)[:message]).to match(/undo_staged_item/)
    end
  end

  describe "undo_staged_item" do
    let!(:item) { create(:ingestion_item, ingestion_run: run) }

    it "removes a dish it had put on the live menu" do
      Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
      )

      expect {
        Tools::Ingestion::UndoStagedItem.call(item_id: item.id, server_context: ctx(owner))
      }.to change(Item, :count).by(-1)

      expect(item.reload.decision).to eq("pending")
    end

    it "restores a live dish that an accept had updated" do
      existing = create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco",
                                           description: "Original.")
      item.update!(matched_item_id: existing.id, match_score: 1.0, description: "Overwritten.")

      Tools::Ingestion::AcceptStagedItems.call(
        scan_id: run.id, item_ids: [item.id], server_context: ctx(owner)
      )
      expect(existing.reload.description).to eq("Overwritten.")

      Tools::Ingestion::UndoStagedItem.call(item_id: item.id, server_context: ctx(owner))

      expect(existing.reload.description).to eq("Original.")
    end

    it "says there is nothing to undo on a pending dish" do
      response = Tools::Ingestion::UndoStagedItem.call(item_id: item.id, server_context: ctx(owner))

      expect(response.to_h[:isError]).to be(true)
    end
  end
end
