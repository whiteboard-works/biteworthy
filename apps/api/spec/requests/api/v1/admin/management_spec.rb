require "rails_helper"

# Restaurant/item/user management — the last Avo-parity surface. The
# contracts that matter: restaurant status writes go through the model
# enum (and slug stays immutable — it's the SEO URL + lookup key), an
# admin item "removed" disappears from the public menu (first real
# user of that status), confidence is NOT editable through this
# surface (strict-mode safety stays on the promote rails), and the
# self-demotion guard means the system can't reach zero admins.
RSpec.describe "Admin management endpoints", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "restaurants" do
    it "lists with status filter and suggested-items counts" do
      needs_review = create(:restaurant, :published)
      create(:item, restaurant: needs_review, confidence: "suggested")
      create(:item, restaurant: needs_review, confidence: "confirmed")
      create(:restaurant, name: "Draft Cafe", status: "draft")

      get "/api/v1/admin/restaurants", params: { status: "published" },
                                       headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body["restaurants"]
      expect(rows.map { |r| r["id"] }).to eq([needs_review.id])
      expect(rows.first).to include("items_count" => 2, "suggested_items_count" => 1)
    end

    it "updates fields + status but refuses slug changes" do
      restaurant = create(:restaurant, :published)

      patch "/api/v1/admin/restaurants/#{restaurant.id}",
            params: { status: "closed", about: "Gone fishing" },
            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(restaurant.reload).to have_attributes(status: "closed", about: "Gone fishing")

      patch "/api/v1/admin/restaurants/#{restaurant.id}",
            params: { slug: "new-slug" },
            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "immutable_field", "fields" => ["slug"])

      patch "/api/v1/admin/restaurants/#{restaurant.id}",
            params: { status: "bogus" },
            headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows detail with per-confidence item counts" do
      restaurant = create(:restaurant, :published)
      create(:item, restaurant: restaurant, confidence: "confirmed")
      create(:item, restaurant: restaurant, confidence: "suggested")

      get "/api/v1/admin/restaurants/#{restaurant.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["items_by_confidence"])
        .to eq("confirmed" => 1, "suggested" => 1)
    end
  end

  describe "items" do
    it "lists every status where the public endpoint hides non-published" do
      restaurant = create(:restaurant, :published)
      live    = create(:item, restaurant: restaurant, status: "published")
      removed = create(:item, restaurant: restaurant, status: "removed")

      get "/api/v1/admin/restaurants/#{restaurant.id}/items", headers: auth_headers_for(admin)

      ids = response.parsed_body["items"].map { |i| i["id"] }
      expect(ids).to contain_exactly(live.id, removed.id)
    end

    it "unpublishes via status: removed and the public menu stops serving it" do
      restaurant = create(:restaurant, :published)
      item = create(:item, restaurant: restaurant, status: "published")

      patch "/api/v1/admin/items/#{item.id}", params: { status: "removed" },
                                              headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(item.reload.status).to eq("removed")

      get "/api/v1/restaurants/#{restaurant.id}/items"
      expect(response.parsed_body["items"].map { |i| i["id"] }).not_to include(item.id)
    end

    it "ignores confidence and array params entirely" do
      item = create(:item, confidence: "suggested")

      patch "/api/v1/admin/items/#{item.id}",
            params: { name: "Renamed", confidence: "confirmed", ingredient_ids: ["x"] },
            headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(item.reload).to have_attributes(name: "Renamed", confidence: "suggested")
      expect(response.parsed_body["confidence"]).to eq("suggested")
    end

    it "rejects unknown statuses" do
      item = create(:item)
      patch "/api/v1/admin/items/#{item.id}", params: { status: "vanished" },
                                              headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["allowed"]).to eq(%w[draft published removed])
    end
  end

  describe "users" do
    it "searches by email/handle and reports contribution counts" do
      target = create(:user, email: "findme@example.com")
      create(:review, user: target)
      create(:user)

      get "/api/v1/admin/users", params: { q: "findme" }, headers: auth_headers_for(admin)

      rows = response.parsed_body["users"]
      expect(rows.map { |u| u["id"] }).to eq([target.id])
      expect(rows.first).to include("reviews_count" => 1, "is_admin" => false)
    end

    it "promotes and demotes others but refuses self-demotion" do
      other = create(:user)

      patch "/api/v1/admin/users/#{other.id}", params: { is_admin: true },
                                               headers: auth_headers_for(admin)
      expect(response).to have_http_status(:ok)
      expect(other.reload.is_admin).to be true

      patch "/api/v1/admin/users/#{admin.id}", params: { is_admin: false },
                                               headers: auth_headers_for(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "cannot_demote_self")
      expect(admin.reload.is_admin).to be true
    end

    it "404s non-admins" do
      get "/api/v1/admin/users", headers: auth_headers_for(create(:user))
      expect(response).to have_http_status(:not_found)
    end
  end
end
