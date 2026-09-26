require "rails_helper"

# The scan screen's door. It exists so checking on a scan is a row read,
# not a model round — and so the review screen shows people plain dish
# text instead of the fenced text a model gets.
RSpec.describe "Api::V1::Scans", type: :request do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, :staged, user: owner, restaurant: restaurant) }
  let!(:beef)      { create(:ingredient, name: "Beef", slug: "meat-beef", path: "meat.beef") }

  def json = response.parsed_body

  describe "GET /api/v1/scans/:id" do
    it "answers without calling the model" do
      create(:ingestion_item, ingestion_run: run)
      expect(AnthropicClient).not_to receive(:new)

      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to include("ready" => true, "dish_count" => 1)
    end

    it "shows people the plain dish text, not the model's fenced copy" do
      create(:ingestion_item, ingestion_run: run, name: "Carne Asada Taco")

      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(owner)

      dish = json["dishes"].first
      expect(dish["name"]).to eq("Carne Asada Taco")
      expect(dish["ingredients"]).to include("Beef")
    end

    # Unmatched text means the filter will be missing an ingredient, which
    # matters for allergies — the review screen has to be able to say so.
    it "flags a dish with nothing matched as needing attention" do
      create(:ingestion_item, ingestion_run: run, ingredients_payload: [])

      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(owner)

      expect(json["dishes"].first["needs_attention"]).to be(true)
    end

    it "leaves dishes out until the scan is ready" do
      extracting = create(:ingestion_run, :extracting, user: owner, restaurant: restaurant)

      get "/api/v1/scans/#{extracting.id}", headers: auth_headers_for(owner)

      expect(json["ready"]).to be(false)
      expect(json).not_to have_key("dishes")
    end

    it "hides someone else's scan as not found" do
      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/scans/:id/accept" do
    it "puts every pending dish on the live menu" do
      create(:ingestion_item, ingestion_run: run, name: "Carne Asada Taco")

      expect { post "/api/v1/scans/#{run.id}/accept", params: { all: true }, headers: auth_headers_for(owner) }
        .to change { restaurant.items.count }.by(1)
      expect(json["remaining_pending"]).to eq(0)
    end

    it "refuses someone else's scan" do
      create(:ingestion_item, ingestion_run: run)

      expect { post "/api/v1/scans/#{run.id}/accept", params: { all: true }, headers: auth_headers_for(create(:user)) }
        .not_to change(Item, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/scans" do
    # The quota lives in the tool; this door must not be a way around it.
    it "reports a spent quota as 429 with a sentence to show" do
      allow(Ingestion::StartRun).to receive(:call)
        .and_return(Ingestion::StartRun::Result.new(error: :quota_exceeded))

      post "/api/v1/scans", params: { restaurant: restaurant.slug, source_text: "Taco" },
                            headers: auth_headers_for(owner)

      expect(response).to have_http_status(:too_many_requests)
      expect(json).to include("code" => "quota_exceeded", "error" => a_string_including("Daily scan limit"))
    end
  end
end
