require "rails_helper"

# GET /api/v1/restaurants/:restaurant_id/items/:id — single dish. Public
# (optional auth). Covers the `favorited` flag that seeds the detail
# page's save button.
RSpec.describe "GET /api/v1/restaurants/:restaurant_id/items/:id", type: :request do
  let(:restaurant) { create(:restaurant, :published) }
  let!(:taco)      { create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco") }

  def show_path = "/api/v1/restaurants/#{restaurant.id}/items/#{taco.id}"

  it "returns the dish with favorited=false anonymously" do
    get show_path
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include("id" => taco.id, "name" => "Carne Asada Taco", "favorited" => false)
  end

  it "reports favorited=true for a user who saved the dish" do
    user = create(:user)
    create(:favorite_item, user: user, item: taco)

    get show_path, headers: auth_headers_for(user)
    expect(response.parsed_body["favorited"]).to be(true)
  end

  # The detail payload is where the honest-disclosure columns surface to
  # users: each association ships with its own confidence + source so a
  # person can see whether "no gluten flagged" means "a human checked"
  # or "the AI guessed". The menu index deliberately stays UUID-only.
  it "returns detected ingredients and tags with per-association provenance" do
    wheat = create(:ingredient, name: "Wheat", slug: "grain-wheat", path: "grain.wheat", allergen: true)
    ItemIngredient.create!(item: taco, ingredient: wheat, confidence: "inferred", source: "ai")
    tag = create(:tag, name: "Contains gluten", slug: "contains-gluten")
    ItemTag.create!(item: taco, tag: tag, confidence: "confirmed", source: "human")

    get show_path
    body = response.parsed_body

    expect(body["detected_ingredients"]).to include(
      "slug" => "grain-wheat", "name" => "Wheat",
      "confidence" => "inferred", "source" => "ai", "allergen" => true
    )
    expect(body["detected_tags"]).to include(
      "slug" => "contains-gluten", "name" => "Contains gluten",
      "confidence" => "confirmed", "source" => "human"
    )
  end
end
