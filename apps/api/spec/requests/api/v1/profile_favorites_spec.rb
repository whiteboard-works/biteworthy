require "rails_helper"

RSpec.describe "GET /api/v1/profile/favorites", type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published, name: "Ninis Taqueria") }
  let(:taco)       { create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco") }

  it "401s anonymously" do
    get "/api/v1/profile/favorites"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the caller's favorited restaurants and dishes with context" do
    create(:favorite_restaurant, user: user, restaurant: restaurant)
    create(:favorite_item, user: user, item: taco)

    get "/api/v1/profile/favorites", headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["restaurants"]).to contain_exactly(
      hash_including("slug" => restaurant.slug, "name" => "Ninis Taqueria", "status" => "published")
    )
    expect(body["items"].first).to include("name" => "Carne Asada Taco", "status" => "published")
    expect(body["items"].first["restaurant"]).to include("slug" => restaurant.slug)
  end

  it "scopes to the current user (no leak across users)" do
    create(:favorite_restaurant, user: create(:user), restaurant: restaurant)
    create(:favorite_item, user: user, item: taco)

    get "/api/v1/profile/favorites", headers: headers
    body = response.parsed_body
    expect(body["restaurants"]).to be_empty
    expect(body["items"].length).to eq(1)
  end

  it "still lists a favorite whose item was later removed, exposing the status" do
    create(:favorite_item, user: user, item: taco)
    taco.update!(status: "removed")

    get "/api/v1/profile/favorites", headers: headers
    expect(response.parsed_body["items"].first["status"]).to eq("removed")
  end
end
