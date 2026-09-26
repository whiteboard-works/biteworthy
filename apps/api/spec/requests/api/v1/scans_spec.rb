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

    it "flags an unmatched tag as needing attention, same as the model's list" do
      create(:ingestion_item, ingestion_run: run, unresolved_tags: [ "house-special" ])

      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(owner)

      expect(json["dishes"].first).to include("needs_attention" => true,
                                               "unresolved" => { "ingredients" => [], "tags" => [ "house-special" ] })
    end

    # Accepting a matched dish edits the live one. The person has to see
    # that before pressing Accept, or they think they are adding.
    it "says when accepting would edit a dish already on the menu" do
      live = create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco", description: "Old words")
      create(:ingestion_item, ingestion_run: run, name: "Carne Asada Taco", matched_item: live, match_score: 0.95)

      get "/api/v1/scans/#{run.id}", headers: auth_headers_for(owner)

      existing = json["dishes"].first["updates_existing_item"]
      expect(existing).to include("item_id" => live.id, "name" => "Carne Asada Taco", "no_changes" => false)
      expect(existing.dig("diff", "description")).to eq("from" => "Old words", "to" => "Grilled steak, cilantro, onion, lime.")
    end
  end

  describe "POST /api/v1/scans/:id/accept" do
    # The tool reads both as "all", which would publish dishes the person
    # deliberately left unticked.
    it "refuses all and item_ids together rather than publishing everything" do
      picked = create(:ingestion_item, ingestion_run: run)
      create(:ingestion_item, ingestion_run: run)

      expect do
        post "/api/v1/scans/#{run.id}/accept", params: { all: true, item_ids: [ picked.id ] },
                                               headers: auth_headers_for(owner)
      end.not_to change(Item, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

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

  describe "POST /api/v1/scans/:id/reject" do
    # Rejections are the review's "not on the menu" — they count toward the
    # draft's publish threshold, so a draft doesn't go live off one dish.
    it "records unticked dishes as rejected so a draft publishes on a truthful ratio" do
      draft = create(:restaurant, status: "draft", created_by_user_id: owner.id)
      draft_run = create(:ingestion_run, :staged, user: owner, restaurant: draft)
      keep = create(:ingestion_item, ingestion_run: draft_run)
      junk = create_list(:ingestion_item, 2, ingestion_run: draft_run)

      post "/api/v1/scans/#{draft_run.id}/reject", params: { item_ids: junk.map(&:id) },
                                                   headers: auth_headers_for(owner)
      expect(response).to have_http_status(:ok)
      post "/api/v1/scans/#{draft_run.id}/accept", params: { item_ids: [ keep.id ] },
                                                   headers: auth_headers_for(owner)

      expect(json["restaurant_published"]).to be(false)
      expect(draft.reload.status).to eq("draft")
    end
  end

  describe "accept racing reject" do
    # promote! re-reads under the row lock the reject also takes; a dish
    # rejected after its record was loaded must not reach the live menu.
    it "refuses to publish a dish that was rejected after it was loaded" do
      staged = create(:ingestion_item, ingestion_run: run)
      stale  = IngestionItem.find(staged.id)

      post "/api/v1/scans/#{run.id}/reject", params: { item_ids: [ staged.id ] }, headers: auth_headers_for(owner)

      expect { stale.promote!(decided_by: owner) }.to raise_error(/rejected/)
      expect(Item.where(restaurant: restaurant).count).to eq(0)
      expect(staged.reload.decision).to eq("rejected")
    end
  end

  describe "POST /api/v1/scans" do
    it "refuses more than one source instead of silently scanning one of them" do
      expect do
        post "/api/v1/scans", params: { restaurant: restaurant.slug, source_text: "Taco", source_url: "https://example.com/menu" },
                              headers: auth_headers_for(owner)
      end.not_to change(IngestionRun, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Someone else's unpublished draft is not a menu this caller may spend
    # a scan on; a 403 lets the screen say so instead of "check your input".
    it "refuses a draft restaurant the caller did not create with 403" do
      draft = create(:restaurant, status: "draft")

      post "/api/v1/scans", params: { restaurant: draft.slug, source_text: "Taco" },
                            headers: auth_headers_for(owner)

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("forbidden_restaurant")
    end

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
