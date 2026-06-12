require "rails_helper"

# Phase 3.3 — the mobile restaurant page hits this for header info
# (name, city) since the items endpoint only returns restaurant_id.
# Anonymous access is part of the demo: someone scans a menu without
# signing up.

RSpec.describe "GET /api/v1/restaurants/:id", type: :request do
  let(:durango)    { create(:city, slug: "durango") }
  let(:restaurant) { create(:restaurant, :published, city: durango, name: "Ninis Taqueria") }

  it "returns the restaurant + city payload, anonymously" do
    get "/api/v1/restaurants/#{restaurant.id}"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body).to include(
      "id"                 => restaurant.id,
      "slug"               => restaurant.slug,
      "name"               => "Ninis Taqueria",
      "status"             => "published",
      "claimed_at"         => nil,
      "claimed_by_user_id" => nil
    )
    expect(body["city"]).to include(
      "slug"   => "durango",
      "name"   => "Durango",
      "region" => "CO"
    )
  end

  it "404s on a non-existent id" do
    get "/api/v1/restaurants/00000000-0000-0000-0000-000000000000"
    expect(response).to have_http_status(:not_found)
  end

  it "404s on a draft restaurant (not yet published)" do
    draft = create(:restaurant) # default :draft status
    get "/api/v1/restaurants/#{draft.id}"
    expect(response).to have_http_status(:not_found)
  end

  describe "lookup by slug (Phase 3.6 — SEO URLs)" do
    it "resolves a restaurant by its slug" do
      get "/api/v1/restaurants/#{restaurant.slug}"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(restaurant.id)
    end

    it "404s on a slug that doesn't exist" do
      get "/api/v1/restaurants/no-such-restaurant-here"
      expect(response).to have_http_status(:not_found)
    end

    it "404s on a slug for a draft restaurant" do
      draft = create(:restaurant, slug: "secret-place-1")
      get "/api/v1/restaurants/secret-place-1"
      expect(response).to have_http_status(:not_found)
    end
  end
end

# Phase 7.2 — list/search backing the mobile home screen. The :index
# route existed since Phase 0 but had no action (latent 500).
RSpec.describe "Restaurants index API", type: :request do
  let!(:city) { create(:city, slug: "durango") }

  it "lists published restaurants with city + address summary, anonymous OK" do
    r = create(:restaurant, :published, name: "Ninis Taqueria", city: city)
    r.addresses.create!(street: "Main Ave 101", latitude: 37.27, longitude: -107.88)
    create(:restaurant, status: "draft", name: "Hidden Draft", city: city)

    get "/api/v1/restaurants"

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body["restaurants"]
    expect(rows.map { |x| x["name"] }).to eq(["Ninis Taqueria"])
    expect(rows.first).to include(
      "street" => "Main Ave 101", "latitude" => 37.27, "longitude" => -107.88
    )
    expect(rows.first["city"]).to include("slug" => "durango")
  end

  it "filters by ?q= case-insensitively on a substring" do
    create(:restaurant, :published, name: "Thai Kitchen", city: city)
    create(:restaurant, :published, name: "Himalayan Kitchen", city: city)
    create(:restaurant, :published, name: "Ninis Taqueria", city: city)

    get "/api/v1/restaurants", params: { q: "kitchen" }

    names = response.parsed_body["restaurants"].map { |x| x["name"] }
    expect(names).to contain_exactly("Thai Kitchen", "Himalayan Kitchen")
  end

  it "escapes LIKE wildcards in the query" do
    create(:restaurant, :published, name: "100% Tacos", city: city)
    create(:restaurant, :published, name: "Ninis Taqueria", city: city)

    get "/api/v1/restaurants", params: { q: "100%" }

    names = response.parsed_body["restaurants"].map { |x| x["name"] }
    expect(names).to eq(["100% Tacos"])
  end

  it "caps the list at 25 rows" do
    30.times { |i| create(:restaurant, :published, name: "Cafe #{i.to_s.rjust(2, '0')}", city: city) }

    get "/api/v1/restaurants"

    expect(response.parsed_body["restaurants"].length).to eq(25)
  end
end
