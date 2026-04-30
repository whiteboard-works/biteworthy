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
      "id"     => restaurant.id,
      "slug"   => restaurant.slug,
      "name"   => "Ninis Taqueria",
      "status" => "published"
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
end
