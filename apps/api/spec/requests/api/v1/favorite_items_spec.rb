require "rails_helper"

RSpec.describe "POST/DELETE /api/v1/items/:id/favorite", type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }

  describe "POST" do
    it "favorites the dish and echoes the new state" do
      expect {
        post "/api/v1/items/#{item.id}/favorite", headers: headers
      }.to change(FavoriteItem, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("item_id" => item.id, "favorited" => true)
    end

    it "is idempotent (repeat calls don't dup rows)" do
      post "/api/v1/items/#{item.id}/favorite", headers: headers
      expect {
        post "/api/v1/items/#{item.id}/favorite", headers: headers
      }.not_to change(FavoriteItem, :count)
    end

    it "401s anonymously" do
      post "/api/v1/items/#{item.id}/favorite"
      expect(response).to have_http_status(:unauthorized)
    end

    it "stays idempotent (200, not 500) when a concurrent insert wins the race" do
      allow(FavoriteItem).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordNotUnique)

      post "/api/v1/items/#{item.id}/favorite", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("item_id" => item.id, "favorited" => true)
    end

    it "404s for an unpublished item" do
      draft_item = create(:item, restaurant: restaurant) # default :draft
      post "/api/v1/items/#{draft_item.id}/favorite", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE" do
    before { create(:favorite_item, user: user, item: item) }

    it "unfavorites the dish and echoes the new state" do
      expect {
        delete "/api/v1/items/#{item.id}/favorite", headers: headers
      }.to change(FavoriteItem, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("item_id" => item.id, "favorited" => false)
    end

    it "is idempotent (unfavoriting an absent row returns ok)" do
      delete "/api/v1/items/#{item.id}/favorite", headers: headers # first call
      expect {
        delete "/api/v1/items/#{item.id}/favorite", headers: headers
      }.not_to change(FavoriteItem, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
