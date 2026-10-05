# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/admin/restaurants/:restaurant_id/backfill_structure" do
  let(:admin)      { create(:user, is_admin: true, password: "password123") }
  let(:user)       { create(:user, is_admin: false, password: "password123") }
  let(:restaurant) { create(:restaurant, :published) }

  def headers_for(account)
    { "Authorization" => "Bearer #{jwt_for(account)}" }
  end

  def jwt_for(account)
    Warden::JWTAuth::UserEncoder.new.call(account, :user, nil).first
  end

  describe "authorization" do
    it "requires admin access" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(user)

      expect(response).to have_http_status(:not_found)
    end

    it "allows admins" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "backfill execution" do
    let(:run) { create(:ingestion_run, restaurant: restaurant, status: "staged") }

    it "backfills sections and variants from accepted ingestion items" do
      item = create(:item, restaurant: restaurant, status: "published")
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             section_name: "Tacos",
             prices_payload: [ { "size" => "small", "price_cents" => 450 } ])

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["sections_created"].size).to eq(1)
      expect(body["variants_added"].size).to eq(1)
      expect(body["dry_run"]).to be false

      expect(item.reload.menu_section&.name).to eq("Tacos")
      expect(item.item_variants.count).to eq(1)
    end

    it "supports dry_run mode" do
      item = create(:item, restaurant: restaurant, status: "published")
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             section_name: "Appetizers")

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           params: { dry_run: true },
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["dry_run"]).to be true
      expect(body["sections_created"].size).to eq(1)

      expect(item.reload.menu_section).to be_nil
    end

    it "returns 404 for nonexistent restaurant" do
      post "/api/v1/admin/restaurants/00000000-0000-0000-0000-000000000000/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:not_found)
    end
  end
end
