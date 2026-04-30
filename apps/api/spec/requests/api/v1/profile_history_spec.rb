require "rails_helper"

RSpec.describe "GET /api/v1/profile/history", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  let(:durango)        { create(:city, slug: "durango") }
  let(:r1)             { create(:restaurant, :published, city: durango, name: "Ninis Taqueria") }
  let(:r2)             { create(:restaurant, :published, city: durango, name: "Cream Bean Berry") }

  it "401s anonymously" do
    get "/api/v1/profile/history"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns visits newest-first with restaurant + city + counts" do
    create(:restaurant_visit, user: user, restaurant: r1, viewed_on: 2.days.ago.to_date,
           items_visible_count: 3, items_hidden_count: 1, updated_at: 2.days.ago)
    create(:restaurant_visit, user: user, restaurant: r2, viewed_on: 1.day.ago.to_date,
           items_visible_count: 8, items_hidden_count: 0, updated_at: 1.day.ago)

    get "/api/v1/profile/history", headers: headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["total"]).to eq(2)
    names = body["visits"].map { |v| v["restaurant"]["name"] }
    expect(names).to eq(["Cream Bean Berry", "Ninis Taqueria"])

    first = body["visits"].first
    expect(first).to include(
      "items_visible_count" => 8,
      "items_hidden_count"  => 0
    )
    expect(first["restaurant"]).to include(
      "slug" => r2.slug,
      "name" => "Cream Bean Berry"
    )
    expect(first["restaurant"]["city"]).to include(
      "slug" => "durango", "name" => "Durango", "region" => "CO"
    )
  end

  it "respects limit + offset" do
    3.times do |i|
      create(:restaurant_visit, user: user, restaurant: r1,
             viewed_on: i.days.ago.to_date, updated_at: i.days.ago)
    end

    get "/api/v1/profile/history?limit=1&offset=1", headers: headers
    expect(response.parsed_body["visits"].length).to eq(1)
    expect(response.parsed_body["total"]).to eq(3)
  end

  it "scopes to the current user (no leak across users)" do
    create(:restaurant_visit, user: user, restaurant: r1)
    create(:restaurant_visit, user: create(:user), restaurant: r2)

    get "/api/v1/profile/history", headers: headers
    expect(response.parsed_body["total"]).to eq(1)
  end
end
