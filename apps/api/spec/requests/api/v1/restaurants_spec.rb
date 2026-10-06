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

  it "reports favorited=false anonymously and true for a user who saved it" do
    get "/api/v1/restaurants/#{restaurant.id}"
    expect(response.parsed_body["favorited"]).to be(false)

    user = create(:user)
    create(:favorite_restaurant, user: user, restaurant: restaurant)
    get "/api/v1/restaurants/#{restaurant.id}", headers: auth_headers_for(user)
    expect(response.parsed_body["favorited"]).to be(true)
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

  describe "address in response" do
    it "includes full address when available" do
      restaurant.addresses.create!(
        street: "123 Main St",
        city: "Durango",
        region: "CO",
        postal_code: "81301",
        country: "USA"
      )

      get "/api/v1/restaurants/#{restaurant.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["address"]).to include(
        "street"      => "123 Main St",
        "city"        => "Durango",
        "region"      => "CO",
        "postal_code" => "81301",
        "country"     => "USA"
      )
    end

    it "returns null address when none exists" do
      get "/api/v1/restaurants/#{restaurant.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["address"]).to be_nil
    end
  end

  describe "hours and timezone in response" do
    let(:denver_city) { create(:city, slug: "denver", region: "Colorado", time_zone: "America/Denver") }
    let(:restaurant_with_hours) { create(:restaurant, :published, city: denver_city) }

    it "includes timezone from city" do
      get "/api/v1/restaurants/#{restaurant_with_hours.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["time_zone"]).to eq("America/Denver")
    end

    it "includes empty hours array when no hours exist" do
      get "/api/v1/restaurants/#{restaurant_with_hours.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["hours"]).to eq([])
    end

    it "includes hours sorted by day and opening time" do
      # Dinner shift Monday
      restaurant_with_hours.hours.create!(day_of_week: 1, opens_at: "17:00", closes_at: "21:00")
      # Lunch shift Monday (added second to test sorting)
      restaurant_with_hours.hours.create!(day_of_week: 1, opens_at: "11:00", closes_at: "14:00")
      # Sunday
      restaurant_with_hours.hours.create!(day_of_week: 0, opens_at: "12:00", closes_at: "20:00")

      get "/api/v1/restaurants/#{restaurant_with_hours.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["hours"]).to eq([
        { "day_of_week" => 0, "opens_at" => "12:00", "closes_at" => "20:00" },
        { "day_of_week" => 1, "opens_at" => "11:00", "closes_at" => "14:00" },
        { "day_of_week" => 1, "opens_at" => "17:00", "closes_at" => "21:00" }
      ])
    end

    it "handles overnight shifts that close after midnight" do
      restaurant_with_hours.hours.create!(day_of_week: 5, opens_at: "22:00", closes_at: "02:00")

      get "/api/v1/restaurants/#{restaurant_with_hours.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["hours"].first).to include(
        "day_of_week" => 5,
        "opens_at" => "22:00",
        "closes_at" => "02:00"
      )
    end

    it "handles closed days with null times" do
      restaurant_with_hours.hours.create!(day_of_week: 2, opens_at: nil, closes_at: nil)

      get "/api/v1/restaurants/#{restaurant_with_hours.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["hours"].first).to eq(
        "day_of_week" => 2,
        "opens_at" => nil,
        "closes_at" => nil
      )
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
    expect(rows.first["address"]).to include("street" => "Main Ave 101")
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

  it "caps the list at INDEX_LIMIT rows, which must clear the 30-restaurant launch seed" do
    # The web browse page (and its local name search) treats this response
    # as the complete published list — a cap under the real count turns
    # into silent truncation there and false "no matches" in search.
    expect(Api::V1::RestaurantsController::INDEX_LIMIT).to be >= 30

    (Api::V1::RestaurantsController::INDEX_LIMIT + 5).times do |i|
      create(:restaurant, :published, name: "Cafe #{i.to_s.rjust(3, '0')}", city: city)
    end

    get "/api/v1/restaurants"

    expect(response.parsed_body["restaurants"].length)
      .to eq(Api::V1::RestaurantsController::INDEX_LIMIT)
  end
end
