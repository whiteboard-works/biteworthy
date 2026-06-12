require "rails_helper"

# Phase 6.2 — community restaurant creation + pg_trgm dedup guard.
RSpec.describe "Restaurant creation API", type: :request do
  let(:city) { create(:city, slug: "durango") }
  let(:user) { create(:user, password: "password123", is_admin: false) }

  def auth_for(u)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(u, :user, nil)
    { "Authorization" => "Bearer #{token}" }
  end

  def create_restaurant(as: user, **params)
    post "/api/v1/restaurants", params: params, headers: auth_for(as)
  end

  describe "POST /api/v1/restaurants" do
    it "creates a draft restaurant recording the creator" do
      expect {
        create_restaurant(name: "Maria's Tacos", city_slug: city.slug)
      }.to change(Restaurant, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to   eq("Maria's Tacos")
      expect(body["status"]).to eq("draft")
      expect(body["slug"]).to   eq("maria-s-tacos")
      expect(body["city"]["slug"]).to eq("durango")
      expect(Restaurant.find(body["id"]).created_by_user_id).to eq(user.id)
    end

    it "suffixes the slug on collision" do
      create(:restaurant, name: "Maria's Tacos", slug: "maria-s-tacos", city: city)

      create_restaurant(name: "Maria's Tacos", city_slug: city.slug, force: true)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["slug"]).to eq("maria-s-tacos-2")
    end

    it "attaches an address when street is given" do
      create_restaurant(name: "Maria's Tacos", city_slug: city.slug,
                        street: "742 Main Ave", postal_code: "81301")

      restaurant = Restaurant.find(response.parsed_body["id"])
      expect(restaurant.addresses.first).to have_attributes(
        street: "742 Main Ave", postal_code: "81301", city: "Durango", region: "CO"
      )
    end

    it "401s unauthenticated callers" do
      post "/api/v1/restaurants", params: { name: "X", city_slug: city.slug }
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s on an unknown city slug" do
      create_restaurant(name: "Maria's Tacos", city_slug: "atlantis")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to eq("unknown_city")
    end

    it "422s on a blank name" do
      create_restaurant(name: "   ", city_slug: city.slug)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "duplicate detection" do
    let!(:existing) do
      create(:restaurant, :published, name: "Maria's Tacos", slug: "maria-s-tacos", city: city)
    end

    it "409s with candidates when a similar name exists in the same city" do
      expect {
        create_restaurant(name: "Marias Taco", city_slug: city.slug)
      }.not_to change(Restaurant, :count)

      expect(response).to have_http_status(:conflict)
      body = response.parsed_body
      expect(body["error"]).to eq("possible_duplicate")
      expect(body["candidates"].first).to include(
        "id" => existing.id, "name" => "Maria's Tacos", "status" => "published"
      )
    end

    it "force: true creates anyway after the client showed the prompt" do
      expect {
        create_restaurant(name: "Marias Taco", city_slug: city.slug, force: true)
      }.to change(Restaurant, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "the same name in a DIFFERENT city is not a duplicate" do
      other_city = create(:city, slug: "telluride")

      create_restaurant(name: "Maria's Tacos", city_slug: other_city.slug)

      expect(response).to have_http_status(:created)
    end

    it "an unrelated name in the same city is not a duplicate" do
      create_restaurant(name: "Golden Dragon Noodle House", city_slug: city.slug)

      expect(response).to have_http_status(:created)
    end
  end
end
