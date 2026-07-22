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
end
