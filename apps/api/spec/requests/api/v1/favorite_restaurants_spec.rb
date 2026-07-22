require "rails_helper"

RSpec.describe "POST/DELETE /api/v1/restaurants/:restaurant_id/favorite", type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published) }

  describe "POST" do
    it "favorites the restaurant and echoes the new state" do
      expect {
        post "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers
      }.to change(FavoriteRestaurant, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("restaurant_id" => restaurant.id, "favorited" => true)
    end

    it "accepts the slug as well as the id" do
      post "/api/v1/restaurants/#{restaurant.slug}/favorite", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["favorited"]).to be(true)
    end

    it "is idempotent (repeat calls don't dup rows)" do
      post "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers
      expect {
        post "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers
      }.not_to change(FavoriteRestaurant, :count)
    end

    it "401s anonymously" do
      post "/api/v1/restaurants/#{restaurant.id}/favorite"
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unpublished restaurant" do
      draft = create(:restaurant) # default :draft
      post "/api/v1/restaurants/#{draft.id}/favorite", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE" do
    before { create(:favorite_restaurant, user: user, restaurant: restaurant) }

    it "unfavorites the restaurant and echoes the new state" do
      expect {
        delete "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers
      }.to change(FavoriteRestaurant, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("restaurant_id" => restaurant.id, "favorited" => false)
    end

    it "is idempotent (unfavoriting an absent row returns ok)" do
      delete "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers # first call
      expect {
        delete "/api/v1/restaurants/#{restaurant.id}/favorite", headers: headers
      }.not_to change(FavoriteRestaurant, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
