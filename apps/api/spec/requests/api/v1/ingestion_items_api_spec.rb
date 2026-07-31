require "rails_helper"

RSpec.describe "Ingestion items API (PATCH/INDEX)", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let(:admin)      { create(:user, password: "password123", is_admin: true) }
  let(:non_admin)  { create(:user, password: "password123", is_admin: false) }
  let(:run)        { create(:ingestion_run, :staged, restaurant: restaurant) }

  let!(:beef)  { create(:ingredient, slug: "meat-beef") }
  let!(:taco_tag) { create(:tag, slug: "cuisine-mexican") }

  let!(:item) do
    create(:ingestion_item,
           ingestion_run: run, name: "Carne Asada Taco",
           ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.97 }],
           tags_payload:        [{ "slug" => "cuisine-mexican", "confidence" => 0.99 }])
  end

  def auth_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  describe "GET /api/v1/ingestion_runs/:run_id/items" do
    it "lists items for the run" do
      get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["items"].length).to eq(1)
      expect(body["items"].first["name"]).to eq("Carne Asada Taco")
    end

    it "rejects non-admins who aren't the run's creator with 403" do
      get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(non_admin)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "community self-verify (Phase 6.3)" do
    let(:scanner) { create(:user, password: "password123", is_admin: false) }
    let(:community_run) do
      create(:ingestion_run, :staged, restaurant: restaurant, user: scanner)
    end
    let!(:community_item) do
      create(:ingestion_item,
             ingestion_run: community_run, name: "Pad Thai",
             ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.95 }],
             tags_payload:        [{ "slug" => "cuisine-mexican", "confidence" => 0.92 }])
    end

    def accept_as(user)
      patch "/api/v1/ingestion_runs/#{community_run.id}/items/#{community_item.id}",
            params: { decision: "accepted" }.to_json,
            headers: auth_for(user)
    end

    it "lets the run's creator list its items" do
      get "/api/v1/ingestion_runs/#{community_run.id}/items", headers: auth_for(scanner)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items"].first["name"]).to eq("Pad Thai")
    end

    it "403s a different non-admin even on an owned run" do
      stranger = create(:user, password: "password123", is_admin: false)
      get "/api/v1/ingestion_runs/#{community_run.id}/items", headers: auth_for(stranger)

      expect(response).to have_http_status(:forbidden)
    end

    it "creator acceptance promotes with confidence: suggested on the Item AND the joins" do
      accept_as(scanner)

      expect(response).to have_http_status(:ok)
      promoted = Item.find(response.parsed_body["item_id"])
      expect(promoted.confidence).to eq("suggested")
      expect(promoted.item_ingredients.pluck(:confidence, :source)).to all(eq(%w[suggested human]))
      expect(promoted.item_tags.pluck(:confidence, :source)).to        all(eq(%w[suggested human]))
    end

    it "admin acceptance of the same run promotes with confidence: confirmed" do
      accept_as(admin)

      promoted = Item.find(response.parsed_body["item_id"])
      expect(promoted.confidence).to eq("confirmed")
      expect(promoted.item_ingredients.pluck(:confidence)).to all(eq("confirmed"))
      expect(promoted.item_tags.pluck(:confidence)).to        all(eq("confirmed"))
    end

    it "end-to-end: a community-promoted item is hidden from strict mode, visible to balanced" do
      accept_as(scanner)
      promoted_id = response.parsed_body["item_id"]

      get "/api/v1/restaurants/#{restaurant.id}/items", params: { strictness: "strict" }
      strict_row = response.parsed_body["items"].find { |i| i["id"] == promoted_id }
      expect(strict_row["status"]).to eq("hidden")
      expect(strict_row["reasons"].map { |r| r["kind"] }).to include("unconfirmed_strict")

      get "/api/v1/restaurants/#{restaurant.id}/items", params: { strictness: "balanced" }
      balanced_row = response.parsed_body["items"].find { |i| i["id"] == promoted_id }
      expect(balanced_row["status"]).to eq("visible")
    end
  end

  describe "PATCH /api/v1/ingestion_runs/:run_id/items/:id" do
    context "decision: accepted" do
      it "promotes the item, fills in decision/decided_at/item_id" do
        expect {
          patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
                params: { decision: "accepted" }.to_json,
                headers: auth_for(admin)
        }.to change(Item, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["decision"]).to     eq("accepted")
        expect(body["item_id"]).to      be_present
        expect(body["decided_at"]).to    be_present

        promoted = Item.find(body["item_id"])
        expect(promoted.ingredients).to contain_exactly(beef)
        expect(promoted.tags).to        contain_exactly(taco_tag)
      end

      it "materializes prices_payload as ItemVariants on the promoted Item" do
        item.update!(prices_payload: [
          { "size" => "small", "price_cents" => 450 },
          { "size" => "large", "price_cents" => 750 }
        ])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted" }.to_json,
              headers: auth_for(admin)

        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_variants.order(:position).pluck(:size, :price_cents))
          .to eq([["small", 450], ["large", 750]])
      end

      # Fixing a misread price at verify time is the whole point of
      # editing upstream: the promoted Item must carry the corrected
      # number, never the extractor's.
      it "materializes EDITED prices, not the extracted ones" do
        item.update!(prices_payload: [{ "size" => nil, "price_cents" => 1_950 }])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: {
                decision:       "accepted",
                prices_payload: [
                  { "size" => "half", "price_cents" => 895 },
                  { "size" => "full", "price_cents" => 1_495 }
                ]
              }.to_json,
              headers: auth_for(admin)

        expect(response).to have_http_status(:ok)
        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_variants.order(:position).pluck(:size, :price_cents))
          .to eq([["half", 895], ["full", 1_495]])
      end

      it "an edited empty prices array clears the payload (no variants promoted)" do
        item.update!(prices_payload: [{ "size" => nil, "price_cents" => 450 }])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted", prices_payload: [] }.to_json,
              headers: auth_for(admin)

        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_variants).to be_empty
        expect(item.reload.prices_payload).to eq([])
      end

      it "leaves the stored prices alone when the key is omitted" do
        item.update!(prices_payload: [{ "size" => nil, "price_cents" => 450 }])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted", name: "Renamed only" }.to_json,
              headers: auth_for(admin)

        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_variants.pluck(:price_cents)).to eq([450])
      end

      # Before edits were allowed, price_cents could only come from the
      # extractor's schema-constrained output. A human editing straight
      # into a published menu needs the same floor.
      it "422s a negative or non-numeric price without touching the item" do
        item.update!(prices_payload: [{ "size" => nil, "price_cents" => 450 }])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted", prices_payload: [{ "price_cents" => -500 }] }.to_json,
              headers: auth_for(admin)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq("invalid_price_cents")
        expect(item.reload.decision).to eq("pending")
        expect(item.prices_payload).to eq([{ "size" => nil, "price_cents" => 450 }])

        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted", prices_payload: [{ "price_cents" => "free" }] }.to_json,
              headers: auth_for(admin)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(item.reload.decision).to eq("pending")
      end

      it "applies edit overrides BEFORE promoting (so the live Item has the human's tweaks)" do
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: {
                decision:    "accepted",
                name:        "Steak Taco",
                description: "Hand-shredded carne asada with house chimichurri."
              }.to_json,
              headers: auth_for(admin)

        expect(response).to have_http_status(:ok)
        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.name).to eq("Steak Taco")
        expect(promoted.description).to include("chimichurri")
      end
    end

    context "decision: accepted while the run is still enriching (:resolving)" do
      # Verify-flow redesign: a resolving run's dishes are visible + acceptable,
      # but promote! must wait until enrichment fills the ingredient/tag payloads
      # — an Item can't go live without them. The acceptance is recorded now and
      # ResolveItemsJob batch-promotes it at :staged.
      let(:resolving_run) do
        create(:ingestion_run, restaurant: restaurant, user: non_admin, status: "resolving")
      end
      let!(:resolving_item) do
        create(:ingestion_item, ingestion_run: resolving_run, name: "Enchilada", position: 0)
      end

      it "records the acceptance but defers promotion (no Item created yet)" do
        expect {
          patch "/api/v1/ingestion_runs/#{resolving_run.id}/items/#{resolving_item.id}",
                params: { decision: "accepted" }.to_json,
                headers: auth_for(non_admin)
        }.not_to change(Item, :count)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["decision"]).to eq("accepted")
        expect(body["item_id"]).to  be_nil
        expect(resolving_item.reload.decided_at).to be_present
      end
    end

    context "addons (add-on guard)" do
      before do
        item.update!(addons_payload: [
          { "name" => "guajillo-tomatillo salsa", "price_cents" => 400, "source" => "extract" },
          { "name" => "chips", "price_cents" => 300, "source" => "guard" }
        ])
      end

      it "serializes addons_payload on index" do
        get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(admin)

        addons = response.parsed_body["items"].first["addons_payload"]
        expect(addons.map { |a| a["name"] }).to eq(["guajillo-tomatillo salsa", "chips"])
      end

      it "promotes addons to ItemModifiers on accept" do
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted" }.to_json,
              headers: auth_for(admin)

        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_modifiers.pluck(:name, :kind, :price_cents)).to contain_exactly(
          ["guajillo-tomatillo salsa", "addition", 400],
          ["chips", "addition", 300]
        )
      end

      it "lets an edit replace addons_payload before accept (drop a wrongly-folded addon)" do
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: {
                decision:       "accepted",
                addons_payload: [{ name: "guajillo-tomatillo salsa", price_cents: 400, source: "extract" }]
              }.to_json,
              headers: auth_for(admin)

        promoted = Item.find(response.parsed_body["item_id"])
        expect(promoted.item_modifiers.pluck(:name)).to eq(["guajillo-tomatillo salsa"])
      end
    end

    context "decision: edited (without accepting)" do
      it "saves the edited fields but does NOT materialize an Item" do
        expect {
          patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
                params: { decision: "edited", name: "Veggie Taco" }.to_json,
                headers: auth_for(admin)
        }.not_to change(Item, :count)

        item.reload
        expect(item.decision).to eq("edited")
        expect(item.name).to     eq("Veggie Taco")
        expect(item.item).to     be_nil
      end
    end

    context "decision: rejected" do
      it "marks the item rejected, no Item created" do
        expect {
          patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
                params: { decision: "rejected" }.to_json,
                headers: auth_for(admin)
        }.not_to change(Item, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["decision"]).to eq("rejected")
      end
    end

    it "422s on an unknown decision value" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "yolo" }.to_json,
            headers: auth_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("invalid_decision")
    end

    it "rejects a non-admin who isn't the run's creator with 403" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted" }.to_json,
            headers: auth_for(non_admin)

      expect(response).to have_http_status(:forbidden)
    end

    it "401s without a token" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted" }.to_json,
            headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "triggers maybe_publish! on the run when the threshold is crossed" do
      # Pre-populate 4 already-accepted items so this is the 5th decision
      # → 5/5 accepted → above threshold.
      4.times do
        ai = create(:ingestion_item, ingestion_run: run, decision: "accepted")
        ai.update_column(:item_id, create(:item, restaurant: restaurant).id)
      end

      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted" }.to_json,
            headers: auth_for(admin)

      expect(response).to have_http_status(:ok)
      expect(run.reload.published?).to be true
    end
  end

  describe "POST /api/v1/ingestion_runs/:run_id/items/accept_all" do
    it "promotes every pending item at once for an enriched (:staged) run" do
      create(:ingestion_item, ingestion_run: run, name: "Bean Taco", position: 1)

      expect {
        post "/api/v1/ingestion_runs/#{run.id}/items/accept_all", headers: auth_for(admin)
      }.to change(Item, :count).by(2)

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.ingestion_items.pluck(:decision)).to all(eq("accepted"))
      expect(run.ingestion_items.pluck(:item_id)).to all(be_present)
    end

    it "defers promotion for a still-resolving run (records accepts, creates no Items)" do
      resolving = create(:ingestion_run, restaurant: restaurant, user: non_admin, status: "resolving")
      create(:ingestion_item, ingestion_run: resolving, name: "A", position: 0)
      create(:ingestion_item, ingestion_run: resolving, name: "B", position: 1)

      expect {
        post "/api/v1/ingestion_runs/#{resolving.id}/items/accept_all", headers: auth_for(non_admin)
      }.not_to change(Item, :count)

      expect(resolving.ingestion_items.pluck(:decision)).to all(eq("accepted"))
      expect(resolving.ingestion_items.pluck(:item_id)).to all(be_nil)
    end

    it "403s a stranger" do
      other    = create(:ingestion_run, :staged, restaurant: restaurant, user: non_admin)
      stranger = create(:user, password: "password123")

      post "/api/v1/ingestion_runs/#{other.id}/items/accept_all", headers: auth_for(stranger)

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Re-scan dedup: matched items serialize a match block + diff, and
  # accepting one APPLIES the scan to the existing Item instead of
  # creating a duplicate. Undo restores what the accept changed.
  describe "re-scan matching" do
    let!(:existing_item) do
      create(:item, restaurant: restaurant, name: "Carne Asada Taco",
                    description: "The original.", status: "published", confidence: "confirmed")
    end

    before do
      ItemVariant.create!(item: existing_item, size: nil, price_cents: 400, position: 0)
      item.update!(matched_item_id: existing_item.id, match_score: 1.0)
    end

    it "serializes the match block with a serialize-time diff on index" do
      get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(admin)

      match = response.parsed_body["items"].first["match"]
      expect(match["item_id"]).to eq(existing_item.id)
      expect(match["score"]).to eq(1.0)
      expect(match["existing"]).to eq(
        "name" => "Carne Asada Taco", "description" => "The original.",
        "prices" => [{ "size" => nil, "price_cents" => 400 }]
      )
      expect(match["diff"]["description"]).to eq(
        "from" => "The original.", "to" => item.description
      )
      expect(match["diff"]["prices"]).to eq(
        "from" => [{ "size" => nil, "price_cents" => 400 }],
        "to"   => [{ "size" => nil, "price_cents" => 450 }]
      )
      expect(match["diff"]["added_ingredients"]).to eq(["meat-beef"])
      expect(match["no_changes"]).to be false
    end

    it "serializes match: null for unmatched rows" do
      unmatched = create(:ingestion_item, ingestion_run: run, name: "Pad Thai", position: 9)

      get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(admin)

      row = response.parsed_body["items"].find { |i| i["id"] == unmatched.id }
      expect(row["match"]).to be_nil
    end

    it "accepting a matched item applies the update instead of creating a duplicate" do
      expect {
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "accepted" }.to_json, headers: auth_for(admin)
      }.not_to change(Item, :count)

      expect(response.parsed_body["item_id"]).to eq(existing_item.id)
      existing_item.reload
      expect(existing_item.description).to eq(item.description)
      expect(existing_item.item_variants.pluck(:price_cents)).to eq([450])
      expect(existing_item.ingredients).to include(beef)
    end

    it "an edited price on a matched card replaces the live item's variants" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: {
              decision:       "accepted",
              prices_payload: [{ "size" => "regular", "price_cents" => 525 }]
            }.to_json,
            headers: auth_for(admin)

      expect(response).to have_http_status(:ok)
      expect(existing_item.reload.item_variants.pluck(:size, :price_cents))
        .to eq([["regular", 525]])
    end

    # Matched-row edits shape what gets ADDED — the append-only contract
    # is what makes undo a safe snapshot restore. Removing a bad chip
    # from a live item is the admin item editor's job, not verify's.
    it "dropping a chip from an edited matched card does NOT remove it from the live item" do
      existing_item.item_ingredients.create!(
        ingredient: beef, confidence: "confirmed", source: "human"
      )

      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted", ingredients_payload: [] }.to_json,
            headers: auth_for(admin)

      expect(response).to have_http_status(:ok)
      expect(existing_item.reload.ingredients).to include(beef)
    end

    # An empty scanned price set means "this scan didn't see prices",
    # never "this dish is free" — so it clears the staged row but leaves
    # the live variants alone. Documented on the endpoint because a
    # verifier who clears the rows sees no change to the live menu.
    it "an emptied price list clears the staged payload but not the live item's variants" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted", prices_payload: [] }.to_json,
            headers: auth_for(admin)

      expect(response).to have_http_status(:ok)
      expect(item.reload.prices_payload).to eq([])
      # Untouched: whatever the live dish already listed.
      expect(existing_item.reload.item_variants.pluck(:price_cents)).to eq([400])
    end

    # The headline regression: before the apply path shipped, undoing an
    # accepted card destroyed whatever item_id pointed at — for an
    # update-accept that would delete a pre-existing live menu item.
    it "undo after an update-accept restores the Item, never destroys it" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted" }.to_json, headers: auth_for(admin)
      expect(response.parsed_body["item_id"]).to eq(existing_item.id)

      expect {
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "pending" }.to_json, headers: auth_for(admin)
      }.not_to change(Item, :count)

      expect(Item.exists?(existing_item.id)).to be true
      existing_item.reload
      expect(existing_item.description).to eq("The original.")
      expect(existing_item.item_variants.pluck(:price_cents)).to eq([400])

      body = response.parsed_body
      expect(body["decision"]).to eq("pending")
      expect(body["item_id"]).to be_nil
      expect(body["match"]["item_id"]).to eq(existing_item.id)
    end

    it "accept_all applies updates and creates side by side" do
      fresh = create(:ingestion_item, ingestion_run: run, name: "Pad Thai", position: 9,
                                      ingredients_payload: [], tags_payload: [])

      expect {
        post "/api/v1/ingestion_runs/#{run.id}/items/accept_all", headers: auth_for(admin)
      }.to change(Item, :count).by(1)

      expect(item.reload.item_id).to eq(existing_item.id)
      expect(fresh.reload.item_id).to be_present
      expect(fresh.item_id).not_to eq(existing_item.id)
    end

    it "a community update-accept downgrades a confirmed Item to suggested" do
      community_run = create(:ingestion_run, :staged, restaurant: restaurant, user: non_admin)
      community_item = create(:ingestion_item,
                              ingestion_run: community_run, name: "Carne Asada Taco",
                              matched_item_id: existing_item.id, match_score: 1.0,
                              ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.9 }],
                              tags_payload: [])

      patch "/api/v1/ingestion_runs/#{community_run.id}/items/#{community_item.id}",
            params: { decision: "accepted" }.to_json, headers: auth_for(non_admin)

      existing_item.reload
      expect(existing_item.confidence).to eq("suggested")
      expect(existing_item.item_ingredients.pluck(:confidence)).to all(eq("suggested"))
    end
  end

  describe "undo (PATCH decision: pending)" do
    it "reverts an accepted+promoted item to pending and removes its live Item + joins" do
      patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
            params: { decision: "accepted" }.to_json, headers: auth_for(admin)
      promoted_id = response.parsed_body["item_id"]
      expect(Item.exists?(promoted_id)).to be true

      expect {
        patch "/api/v1/ingestion_runs/#{run.id}/items/#{item.id}",
              params: { decision: "pending" }.to_json, headers: auth_for(admin)
      }.to change(Item, :count).by(-1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["decision"]).to eq("pending")
      expect(body["item_id"]).to be_nil
      expect(Item.exists?(promoted_id)).to be false
      expect(ItemIngredient.where(item_id: promoted_id)).to be_empty
      # Variants ride the Item's dependent: :destroy — undo must not strand
      # price rows pointing at a dead Item.
      expect(ItemVariant.where(item_id: promoted_id)).to be_empty
    end
  end
end
