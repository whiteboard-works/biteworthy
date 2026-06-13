require "rails_helper"

# Phase 8.5 — tags index backing the taste-onboarding chip picker.
# The route existed since Phase 0 with no controller action.
RSpec.describe "GET /api/v1/tags", type: :request do
  let!(:spicy)   { create(:tag, slug: "flavor-spicy",  name: "Spicy",   family: "flavor") }
  let!(:thai)    { create(:tag, slug: "cuisine-thai",  name: "Thai",    family: "cuisine") }
  let!(:vegan)   { create(:tag, slug: "diet-vegan",    name: "Vegan",   family: "diet") }

  it "is public and returns id/slug/name/family per tag" do
    get "/api/v1/tags"

    expect(response).to have_http_status(:ok)
    row = response.parsed_body["tags"].find { |t| t["slug"] == "flavor-spicy" }
    expect(row).to eq(
      "id" => spicy.id, "slug" => "flavor-spicy", "name" => "Spicy", "family" => "flavor"
    )
  end

  it "filters to a comma-separated subset of families" do
    get "/api/v1/tags", params: { families: "cuisine,flavor" }

    slugs = response.parsed_body["tags"].pluck("slug")
    expect(slugs).to contain_exactly("flavor-spicy", "cuisine-thai")
  end

  it "ignores unknown family names (whitelist, not error)" do
    get "/api/v1/tags", params: { families: "cuisine,'); DROP TABLE tags;--" }

    slugs = response.parsed_body["tags"].pluck("slug")
    expect(slugs).to contain_exactly("cuisine-thai")
  end

  it "caps limit at 200" do
    get "/api/v1/tags", params: { limit: 99_999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["tags"].length).to be <= 200
  end
end
