require "rails_helper"

# WBW-247 — admins must be able to move a restaurant between cities in the
# same state. Lookup is by the trailing slug, so the restaurant slug stays
# put and the old city URL 301/308s via the existing web_path mismatch
# redirect. Non-admins have no write on this field.
RSpec.describe "Admin restaurant city reassignment", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:ogden)   { create(:city, slug: "ogden",   name: "Ogden",   region: "Utah",     country: "US") }
  let!(:draper)  { create(:city, slug: "draper",  name: "Draper",  region: "Utah",     country: "US") }
  let!(:durango) { create(:city, slug: "durango", name: "Durango", region: "Colorado", country: "US") }
  let(:restaurant) do
    create(:restaurant, :published, city: ogden, slug: "laan-thai-restaurant",
                                    name: "Laan Thai Restaurant")
  end

  def admin_headers
    auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  def public_show
    get "/api/v1/restaurants/#{restaurant.slug}"
    response.parsed_body
  end

  it "moves the restaurant to Draper by slug, keeps the slug, and updates the canonical URL" do
    expect(public_show).to include(
      "slug"     => "laan-thai-restaurant",
      "web_path" => "/restaurants/usa/utah/ogden/laan-thai-restaurant"
    )
    expect(public_show["city"]["slug"]).to eq("ogden")

    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: "draper" }.to_json, headers: admin_headers

    expect(response).to have_http_status(:ok)
    expect(restaurant.reload.slug).to eq("laan-thai-restaurant")
    expect(restaurant.city.slug).to eq("draper")

    body = public_show
    expect(body["city"]["slug"]).to eq("draper")
    expect(body["web_path"]).to eq("/restaurants/usa/utah/draper/laan-thai-restaurant")
    expect(body["slug"]).to eq("laan-thai-restaurant")
  end

  it "accepts a city UUID the same way as a slug" do
    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: draper.id }.to_json, headers: admin_headers

    expect(response).to have_http_status(:ok)
    expect(restaurant.reload.city_id).to eq(draper.id)
    expect(restaurant.slug).to eq("laan-thai-restaurant")
  end

  it "accepts a parameterized city name (the MCP repro: city: \"Draper\")" do
    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: "Draper" }.to_json, headers: admin_headers

    expect(response).to have_http_status(:ok)
    expect(restaurant.reload.city.slug).to eq("draper")
  end

  it "422s an unknown city without moving the restaurant" do
    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: "atlantis" }.to_json, headers: admin_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to eq("unknown_city")
    expect(restaurant.reload.city.slug).to eq("ogden")
  end

  it "422s a city in another state without moving the restaurant" do
    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: "durango" }.to_json, headers: admin_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to eq("city_outside_region")
    expect(restaurant.reload.city.slug).to eq("ogden")
  end

  it "404s a non-admin instead of applying the move" do
    user = create(:user)
    patch "/api/v1/admin/restaurants/#{restaurant.id}",
          params: { city: "draper" }.to_json,
          headers: auth_headers_for(user).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:not_found)
    expect(restaurant.reload.city.slug).to eq("ogden")
  end
end
