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
    end
  end
end
