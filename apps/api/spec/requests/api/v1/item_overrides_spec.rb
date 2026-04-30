require "rails_helper"

RSpec.describe "POST/DELETE /api/v1/items/:id/never_hide", type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }

  describe "POST" do
    it "creates a never_hide override and echoes the new state" do
      expect {
        post "/api/v1/items/#{item.id}/never_hide", headers: headers
      }.to change(UserItemOverride, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "item_id"             => item.id,
        "overridden_by_user"  => true
      )
    end

    it "is idempotent (repeat calls don't dup rows)" do
      post "/api/v1/items/#{item.id}/never_hide", headers: headers
      expect {
        post "/api/v1/items/#{item.id}/never_hide", headers: headers
      }.not_to change(UserItemOverride, :count)
    end

    it "401s anonymously" do
      post "/api/v1/items/#{item.id}/never_hide"
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unpublished item (no leaking draft ids)" do
      draft_item = create(:item, restaurant: restaurant) # default :draft
      post "/api/v1/items/#{draft_item.id}/never_hide", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE" do
    before { create(:user_item_override, user: user, item: item) }

    it "removes the override and echoes the new state" do
      expect {
        delete "/api/v1/items/#{item.id}/never_hide", headers: headers
      }.to change(UserItemOverride, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "item_id"             => item.id,
        "overridden_by_user"  => false
      )
    end

    it "is idempotent (deleting an absent override returns ok)" do
      delete "/api/v1/items/#{item.id}/never_hide", headers: headers # first call
      expect {
        delete "/api/v1/items/#{item.id}/never_hide", headers: headers
      }.not_to change(UserItemOverride, :count)
      expect(response).to have_http_status(:ok)
    end
  end
end
