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

    it "orders sections by first appearance in source order" do
      item1 = create(:item, restaurant: restaurant, status: "published")
      item2 = create(:item, restaurant: restaurant, status: "published")
      item3 = create(:item, restaurant: restaurant, status: "published")

      # Create items in source order: STARTERS, CHICKEN, STARTERS
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item1,
             section_name: "STARTERS",
             position: 0)
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item2,
             section_name: "CHICKEN & LAMB",
             position: 1)
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item3,
             section_name: "STARTERS",
             position: 2)

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)

      # STARTERS should be position 0 (first appearance), CHICKEN should be position 1
      starters_section = item1.reload.menu_section
      chicken_section = item2.reload.menu_section
      expect(starters_section.position).to eq(0)
      expect(chicken_section.position).to eq(1)
      expect(item3.reload.menu_section).to eq(starters_section)
    end

    it "assigns sequential positions to items within sections" do
      item1 = create(:item, restaurant: restaurant, status: "published")
      item2 = create(:item, restaurant: restaurant, status: "published")
      item3 = create(:item, restaurant: restaurant, status: "published")

      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item1,
             section_name: "TACOS",
             position: 0)
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item2,
             section_name: "TACOS",
             position: 1)
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item3,
             section_name: "TACOS",
             position: 2)

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(item1.reload.position).to eq(0)
      expect(item2.reload.position).to eq(1)
      expect(item3.reload.position).to eq(2)
    end

    it "is idempotent when re-run" do
      item = create(:item, restaurant: restaurant, status: "published")
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             section_name: "Tacos",
             position: 0)

      # Run twice
      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)
      expect(response).to have_http_status(:ok)

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)
      expect(response).to have_http_status(:ok)

      # Should still have one section
      expect(restaurant.menus.first.menu_sections.count).to eq(1)
    end

    it "uses latest accepted ingestion item for prices" do
      item = create(:item, restaurant: restaurant, status: "published")

      # Older accepted item
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             prices_payload: [ { "size" => "small", "price_cents" => 450 } ],
             created_at: 2.days.ago)

      # Newer accepted item
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             prices_payload: [ { "size" => "large", "price_cents" => 750 } ],
             created_at: 1.day.ago)

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["variants_added"].size).to eq(1)

      # Should use the newer price
      expect(item.item_variants.count).to eq(1)
      expect(item.item_variants.first.price_cents).to eq(750)
    end

    it "does not overwrite manually edited variant prices by default" do
      item = create(:item, restaurant: restaurant, status: "published")
      ItemVariant.create!(item: item, size: "regular", price_cents: 999, position: 0)

      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             prices_payload: [ { "size" => "small", "price_cents" => 450 } ])

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)

      # Should not overwrite existing variant
      expect(item.item_variants.count).to eq(1)
      expect(item.item_variants.first.price_cents).to eq(999)
    end

    it "overwrites prices when overwrite_prices is true" do
      item = create(:item, restaurant: restaurant, status: "published")
      ItemVariant.create!(item: item, size: "regular", price_cents: 999, position: 0)

      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             prices_payload: [ { "size" => "small", "price_cents" => 450 } ])

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           params: { overwrite_prices: true },
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)

      # Should overwrite existing variant
      expect(item.item_variants.count).to eq(1)
      expect(item.item_variants.first.price_cents).to eq(450)
    end

    it "includes item names and variant details in dry_run response" do
      item = create(:item, restaurant: restaurant, status: "published", name: "Taco")
      create(:ingestion_item,
             ingestion_run: run,
             decision: "accepted",
             item: item,
             section_name: "Tacos",
             prices_payload: [ { "size" => "small", "price_cents" => 450, "currency" => "USD" } ])

      post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_structure",
           params: { dry_run: true },
           headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["dry_run"]).to be true

      variants = body["variants_added"].first
      expect(variants["item_name"]).to eq("Taco")
      expect(variants["count"]).to eq(1)
      expect(variants["variants"].first["size"]).to eq("small")
      expect(variants["variants"].first["price_cents"]).to eq(450)
      expect(variants["variants"].first["currency"]).to eq("USD")

      sections = body["sections_created"].first
      expect(sections["section_name"]).to eq("Tacos")

      # Dry run should not persist
      expect(item.reload.item_variants.count).to eq(0)
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
