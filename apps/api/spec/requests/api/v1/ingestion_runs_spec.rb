require "rails_helper"

RSpec.describe "Ingestion runs API", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let(:admin)      { create(:user, password: "password123", is_admin: true) }
  let(:non_admin)  { create(:user, password: "password123", is_admin: false) }

  def auth_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    { "Authorization" => "Bearer #{token}" }
  end

  def fake_image(name = "page1.jpg")
    Rack::Test::UploadedFile.new(
      StringIO.new("\xFF\xD8\xFF\xE0".b),
      "image/jpeg",
      original_filename: name
    )
  end

  describe "POST /api/v1/ingestion_runs" do
    it "creates a run, attaches inputs, transitions to :extracting, and 201s" do
      # Stub the ExtractMenuJob so we don't try to call Anthropic.
      allow(ExtractMenuJob).to receive(:perform_later)

      expect {
        post "/api/v1/ingestion_runs",
             params: { restaurant_id: restaurant.id, inputs: [fake_image("p1.jpg"), fake_image("p2.jpg")] },
             headers: auth_for(admin)
      }.to change(IngestionRun, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include("status" => "extracting", "input_kind" => "photo", "input_count" => 2)
      expect(ExtractMenuJob).to have_received(:perform_later).with(IngestionRun.last.id)
    end

    it "rejects an unauthenticated caller with 401" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [fake_image] }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a non-admin caller with 403" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [fake_image] },
           headers: auth_for(non_admin)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("forbidden")
    end

    it "422s when no inputs are attached" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id },
           headers: auth_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("no_inputs")
    end

    it "404s on an unknown restaurant" do
      post "/api/v1/ingestion_runs",
           params: { restaurant_id: "00000000-0000-0000-0000-000000000000", inputs: [fake_image] },
           headers: auth_for(admin)

      expect(response).to have_http_status(:not_found)
    end

    it "auto-detects pdf input_kind from content_type" do
      allow(ExtractMenuJob).to receive(:perform_later)
      pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf",
                                         original_filename: "menu.pdf")

      post "/api/v1/ingestion_runs",
           params: { restaurant_id: restaurant.id, inputs: [pdf] },
           headers: auth_for(admin)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["input_kind"]).to eq("pdf")
    end
  end

  describe "GET /api/v1/ingestion_runs/:id" do
    let(:run) { create(:ingestion_run, restaurant: restaurant, user: non_admin) }

    it "lets the run's owner read it" do
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(non_admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(run.id)
    end

    it "lets an admin read any run" do
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(admin)
      expect(response).to have_http_status(:ok)
    end

    it "404s for a different non-admin user" do
      stranger = create(:user, password: "password123", is_admin: false)
      get "/api/v1/ingestion_runs/#{run.id}", headers: auth_for(stranger)
      expect(response).to have_http_status(:not_found)
    end

    it "401s without a token" do
      get "/api/v1/ingestion_runs/#{run.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
