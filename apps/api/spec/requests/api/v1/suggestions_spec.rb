require "rails_helper"

RSpec.describe "Suggestion API", type: :request do
  let(:contributor)  { create(:user) }
  let(:owner)        { create(:user) }
  let(:other_user)   { create(:user) }
  let(:contributor_headers) { auth_headers_for(contributor) }
  let(:owner_headers)       { auth_headers_for(owner) }
  let(:other_headers)       { auth_headers_for(other_user) }

  let(:restaurant) do
    create(:restaurant, :published,
           claimed_at: Time.current,
           claimed_by_user_id: owner.id)
  end
  let(:item)     { create(:item, :published, restaurant: restaurant, name: "Veggie Burrito") }
  let(:cilantro) { create(:ingredient, slug: "herb-cilantro") }

  describe "POST /api/v1/items/:item_id/suggestions" do
    it "creates a pending suggestion (signed in)" do
      expect {
        post "/api/v1/items/#{item.id}/suggestions",
             params:  { kind: "add_ingredient", payload: { ingredient_slug: cilantro.slug } },
             headers: contributor_headers
      }.to change(Suggestion, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include(
        "kind"   => "add_ingredient",
        "status" => "pending"
      )
      expect(body["submitter"]).to include("id" => contributor.id)
    end

    it "accepts anonymous suggestions (user_id stays nil)" do
      expect {
        post "/api/v1/items/#{item.id}/suggestions",
             params: { kind: "rename", payload: { name: "Veggie Burrito (V+GF)" } }
      }.to change(Suggestion, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["submitter"]).to be_nil
    end

    it "422s on an unsupported kind" do
      post "/api/v1/items/#{item.id}/suggestions",
           params: { kind: "make_it_free", payload: {} }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["allowed"]).to include("add_ingredient")
    end

    it "404s on an unpublished item" do
      draft = create(:item, restaurant: restaurant) # default :draft
      post "/api/v1/items/#{draft.id}/suggestions",
           params: { kind: "rename", payload: { name: "X" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/restaurants/:id/suggestions" do
    let!(:pending)  { create(:item_suggestion_pending, subject: item) }
    let!(:accepted) { create(:item_suggestion_pending, subject: item, status: "accepted") }

    it "returns only pending suggestions for the restaurant's items, owner-gated" do
      get "/api/v1/restaurants/#{restaurant.id}/suggestions", headers: owner_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["suggestions"].map { |s| s["id"] }).to eq([pending.id])
    end

    it "403s for a non-owner" do
      get "/api/v1/restaurants/#{restaurant.id}/suggestions", headers: other_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "401s anonymously" do
      get "/api/v1/restaurants/#{restaurant.id}/suggestions"
      expect(response).to have_http_status(:unauthorized)
    end

    it "admins can see any restaurant's queue" do
      admin = create(:user, is_admin: true)
      get "/api/v1/restaurants/#{restaurant.id}/suggestions", headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /api/v1/suggestions/:id" do
    let!(:suggestion) do
      Suggestion.create!(
        user: contributor, subject: item, kind: "add_ingredient", status: "pending",
        payload: { "ingredient_slug" => cilantro.slug }
      )
    end

    it "owner accepts → resolver applies the change + stamps the Suggestion" do
      patch "/api/v1/suggestions/#{suggestion.id}",
            params:  { decision: "accepted" },
            headers: owner_headers

      expect(response).to have_http_status(:ok)
      suggestion.reload
      expect(suggestion.status).to eq("accepted")
      expect(suggestion.resolved_by_user_id).to eq(owner.id)
      expect(item.reload.ingredients).to include(cilantro)
    end

    it "owner rejects → no Item change" do
      patch "/api/v1/suggestions/#{suggestion.id}",
            params:  { decision: "rejected" },
            headers: owner_headers
      expect(suggestion.reload.status).to eq("rejected")
      expect(item.reload.ingredients).to be_empty
    end

    it "403s for a non-owner" do
      patch "/api/v1/suggestions/#{suggestion.id}",
            params:  { decision: "accepted" },
            headers: other_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "422s on an invalid decision string" do
      patch "/api/v1/suggestions/#{suggestion.id}",
            params:  { decision: "maybe" },
            headers: owner_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "422s + InvalidPayloadError surface when the payload is broken" do
      bad = Suggestion.create!(
        user: contributor, subject: item, kind: "add_ingredient", status: "pending",
        payload: { "ingredient_slug" => "no-such-thing" }
      )
      patch "/api/v1/suggestions/#{bad.id}",
            params:  { decision: "accepted" },
            headers: owner_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["kind"]).to eq("InvalidPayloadError")
      expect(bad.reload.status).to eq("pending") # rollback
    end
  end
end
