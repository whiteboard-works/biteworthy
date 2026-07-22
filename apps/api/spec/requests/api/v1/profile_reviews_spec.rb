require "rails_helper"

RSpec.describe "GET /api/v1/profile/reviews", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  let(:restaurant) { create(:restaurant, :published, name: "Ninis Taqueria") }
  let(:taco)   { create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco") }
  let(:burrito) { create(:item, :published, restaurant: restaurant, name: "Bean Burrito") }

  it "401s anonymously" do
    get "/api/v1/profile/reviews"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the caller's reviews newest-first with item + restaurant context" do
    create(:review, user: user, item: taco, rating: 5, body: "Best in town.", created_at: 2.days.ago)
    create(:review, user: user, item: burrito, rating: 3, body: "Fine.", created_at: 1.day.ago)

    get "/api/v1/profile/reviews", headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["total"]).to eq(2)
    expect(body["reviews"].map { |r| r["item"]["name"] }).to eq(["Bean Burrito", "Carne Asada Taco"])

    first = body["reviews"].first
    expect(first).to include("rating" => 3, "body" => "Fine.", "hidden" => false, "hidden_reason" => nil)
    expect(first["item"]).to include("name" => "Bean Burrito", "status" => "published")
    expect(first["item"]["restaurant"]).to include(
      "slug" => restaurant.slug, "name" => "Ninis Taqueria"
    )
  end

  it "still lists a review whose item was later removed, exposing the item status" do
    create(:review, user: user, item: taco, rating: 4, body: "was great")
    taco.update!(status: "removed")

    get "/api/v1/profile/reviews", headers: headers

    body = response.parsed_body
    expect(body["total"]).to eq(1)
    expect(body["reviews"].first["item"]).to include("status" => "removed")
  end

  it "includes the caller's own HIDDEN reviews and says why (unlike the public feed)" do
    review = create(:review, user: user, item: taco, body: "hidden one")
    review.hide!(reason: "spam")

    get "/api/v1/profile/reviews", headers: headers

    body = response.parsed_body
    expect(body["total"]).to eq(1)
    expect(body["reviews"].first).to include("hidden" => true, "hidden_reason" => "spam")
  end

  it "scopes to the current user (no leak across users)" do
    create(:review, user: user, item: taco)
    create(:review, user: create(:user), item: burrito)

    get "/api/v1/profile/reviews", headers: headers
    expect(response.parsed_body["total"]).to eq(1)
  end

  it "respects limit + offset" do
    [taco, burrito, create(:item, :published, restaurant: restaurant)].each_with_index do |item, i|
      create(:review, user: user, item: item, created_at: i.days.ago)
    end

    get "/api/v1/profile/reviews?limit=1&offset=1", headers: headers
    expect(response.parsed_body["reviews"].length).to eq(1)
    expect(response.parsed_body["total"]).to eq(3)
  end
end
