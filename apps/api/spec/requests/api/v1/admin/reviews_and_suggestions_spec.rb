require "rails_helper"

# The admin moderation queues exist because the owner queue only covers
# claimed restaurants and Avo was the only cross-restaurant view. What
# matters: the visibility filters map to the partial-index-backed
# scopes (flagged = reader-reported and not yet moderated), hide
# requires a valid reason (it becomes user-facing "why was this
# hidden" copy), unhide fully restores, and both queues stay behind
# the admin 404 gate.
RSpec.describe "Admin review + suggestion moderation", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/admin/reviews" do
    it "defaults to the flagged (awaiting moderation) queue" do
      flagged = create(:review)
      flagged.report!
      create(:review) # visible, unflagged
      hidden = create(:review)
      hidden.hide!(reason: "abuse")

      get "/api/v1/admin/reviews", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["reviews"].map { |r| r["id"] }).to eq([flagged.id])
      row = body["reviews"].first
      expect(row["flagged_at"]).to be_present
      expect(row.dig("item", "restaurant", "slug")).to be_present
    end

    it "filters by visibility=hidden and rejects unknown visibilities" do
      hidden = create(:review)
      hidden.hide!(reason: "spam")
      create(:review)

      get "/api/v1/admin/reviews", params: { visibility: "hidden" },
                                   headers: auth_headers_for(admin)
      expect(response.parsed_body["reviews"].map { |r| r["id"] }).to eq([hidden.id])
      expect(response.parsed_body["reviews"].first["hidden_reason"]).to eq("spam")

      get "/api/v1/admin/reviews", params: { visibility: "nope" },
                                   headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["allowed"]).to contain_exactly("flagged", "hidden", "visible", "all")
    end

    it "404s non-admins" do
      get "/api/v1/admin/reviews", headers: auth_headers_for(create(:user))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/admin/reviews/:id/hide + unhide" do
    it "hides with a validated reason, clears the flag, and unhide restores" do
      review = create(:review)
      review.report!

      post "/api/v1/admin/reviews/#{review.id}/hide", params: { reason: "duplicate" },
                                                      headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(review.reload).to have_attributes(hidden_reason: "duplicate", flagged_at: nil)
      expect(review.hidden_at).to be_present

      post "/api/v1/admin/reviews/#{review.id}/unhide", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(review.reload).to have_attributes(hidden_at: nil, hidden_reason: nil)
    end

    it "422s an unknown reason without hiding" do
      review = create(:review)

      post "/api/v1/admin/reviews/#{review.id}/hide", params: { reason: "vibes" },
                                                      headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(review.reload.hidden_at).to be_nil
    end
  end

  describe "GET /api/v1/admin/suggestions" do
    it "lists pending suggestions oldest-first across all restaurants" do
      older = create(:item_suggestion_pending, created_at: 2.days.ago)
      newer = create(:item_suggestion_pending)
      create(:item_suggestion_pending, status: "rejected", resolved_at: Time.current)

      get "/api/v1/admin/suggestions", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["suggestions"].map { |s| s["id"] }).to eq([older.id, newer.id])
      expect(body["pagination"]).to include("total" => 2)
    end

    it "filters to one restaurant's items" do
      keep = create(:item_suggestion_pending)
      create(:item_suggestion_pending)
      restaurant_id = keep.subject.restaurant_id

      get "/api/v1/admin/suggestions", params: { restaurant_id: restaurant_id },
                                       headers: auth_headers_for(admin)

      expect(response.parsed_body["suggestions"].map { |s| s["id"] }).to eq([keep.id])
    end

    it "404s non-admins" do
      get "/api/v1/admin/suggestions", headers: auth_headers_for(create(:user))
      expect(response).to have_http_status(:not_found)
    end
  end
end
