require "rails_helper"

# Phase 5.6 — backs the SSR /durango/[diet] SEO pages.
RSpec.describe "GET /api/v1/cities/:city_slug/restaurants", type: :request do
  let(:durango) { create(:city, slug: "durango", name: "Durango", region: "CO") }

  let!(:cheese) { create(:ingredient, slug: "dairy-cheese") }
  let!(:dairy_tag) { create(:tag, slug: "allergen-contains-dairy") }
  let!(:vegan_preset) do
    preset = create(:dietary_profile, slug: "vegan", name: "Vegan")
    create(:dietary_profile_ingredient, dietary_profile: preset, ingredient: cheese, rule: "avoid")
    create(:dietary_profile_tag,        dietary_profile: preset, tag: dairy_tag,    rule: "avoid")
    preset
  end

  let!(:tacos) { create(:restaurant, :published, slug: "tacos", name: "Tacos", city: durango) }
  let!(:cream) { create(:restaurant, :published, slug: "cream", name: "Cream", city: durango) }

  before do
    create(:item, :published, :confirmed, restaurant: tacos, name: "Veggie", ingredients: [])
    create(:item, :published, :confirmed, restaurant: tacos, name: "Cheesy",
           ingredients: [cheese], tag_list: [dairy_tag])
    create(:item, :published, :confirmed, restaurant: cream, name: "Mac",
           ingredients: [cheese], tag_list: [dairy_tag])
  end

  it "returns the city + profile metadata + ranked restaurants" do
    get "/api/v1/cities/durango/restaurants?profile=vegan"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body

    expect(body["city"]).to include(
      "slug" => "durango", "name" => "Durango", "region" => "CO"
    )
    expect(body["profile"]).to include(
      "slug" => "vegan", "name" => "Vegan"
    )
    slugs = body["restaurants"].map { |r| r["slug"] }
    expect(slugs).to eq(%w[tacos cream]) # tacos has 1 vegan-safe item, cream has 0
    expect(body["restaurants"].first).to include(
      "visible_count" => 1, "hidden_count" => 1, "total_count" => 2
    )
  end

  it "404s on an unknown city slug" do
    get "/api/v1/cities/nope/restaurants?profile=vegan"
    expect(response).to have_http_status(:not_found)
  end

  it "404s on an unknown profile slug" do
    get "/api/v1/cities/durango/restaurants?profile=no-such-diet"
    expect(response).to have_http_status(:not_found)
  end

  it "is unauthenticated (anonymous browsers + crawlers)" do
    get "/api/v1/cities/durango/restaurants?profile=vegan"
    expect(response).to have_http_status(:ok)
  end

  it "returns an empty restaurants array when the city has none yet" do
    barren = create(:city, slug: "barren", name: "Barren", region: "WY")
    _ = barren
    get "/api/v1/cities/barren/restaurants?profile=vegan"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["restaurants"]).to eq([])
  end
end
