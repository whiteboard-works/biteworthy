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

    it "rejects non-admins with 403" do
      get "/api/v1/ingestion_runs/#{run.id}/items", headers: auth_for(non_admin)
      expect(response).to have_http_status(:forbidden)
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

    it "rejects a non-admin caller with 403" do
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
end
