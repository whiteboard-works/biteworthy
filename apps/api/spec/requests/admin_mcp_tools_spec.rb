# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin MCP tools" do
  let(:admin) { create(:user, is_admin: true) }
  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "test-city") }
  let(:restaurant) { create(:restaurant, city: city, status: "draft") }

  def mcp_call(tool_name, args, user_context)
    post "/mcp", params: {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: tool_name, arguments: args }
    }.to_json, headers: { "Content-Type": "application/json", "Authorization": "Bearer #{jwt_for(user_context)}" }
  end

  def jwt_for(user)
    Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
  end

  def result_content
    JSON.parse(response.body).dig("result", "content", 0, "text")
      &.then { |text| JSON.parse(text) }
  end

  describe "find_restaurants" do
    before do
      create(:restaurant, name: "Alpha Cafe", city: city, status: "published")
      create(:restaurant, name: "Beta Bistro", city: city, status: "draft")
      create(:restaurant, name: "Closed Place", city: city, status: "closed")
      create(:restaurant, name: "Archived Spot", city: city, status: "published", archived_at: 1.day.ago)
    end

    context "as admin" do
      it "returns all kept restaurants by default" do
        mcp_call("find_restaurants", {}, admin)
        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["restaurants"].size).to eq(3) # excludes archived
      end

      it "filters by name" do
        mcp_call("find_restaurants", { q: "Alpha" }, admin)
        content = result_content
        expect(content["restaurants"].size).to eq(1)
        expect(content["restaurants"][0]["name"]).to eq("Alpha Cafe")
      end

      it "filters by status" do
        mcp_call("find_restaurants", { status: "draft" }, admin)
        content = result_content
        expect(content["restaurants"].size).to eq(1)
        expect(content["restaurants"][0]["name"]).to eq("Beta Bistro")
      end

      it "shows archived when requested" do
        mcp_call("find_restaurants", { archived: true }, admin)
        content = result_content
        expect(content["restaurants"].size).to eq(1)
        expect(content["restaurants"][0]["name"]).to eq("Archived Spot")
      end
    end

    context "as non-admin" do
      it "refuses the call" do
        mcp_call("find_restaurants", {}, user)
        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("forbidden")
      end
    end
  end

  describe "update_restaurant" do
    context "as admin" do
      it "updates basic fields" do
        mcp_call("update_restaurant", {
          restaurant: restaurant.slug,
          name: "New Name",
          about: "New about text",
          website: "https://example.com",
          phone: "555-1234"
        }, admin)

        expect(response).to have_http_status(:ok)
        restaurant.reload
        expect(restaurant.name).to eq("New Name")
        expect(restaurant.about).to eq("New about text")
        expect(restaurant.website).to eq("https://example.com")
        expect(restaurant.phone).to eq("555-1234")
      end

      it "updates address" do
        mcp_call("update_restaurant", {
          restaurant: restaurant.id,
          street: "123 Main St",
          city: "Test City",
          postal_code: "12345",
          latitude: 40.7,
          longitude: -74.0
        }, admin)

        expect(response).to have_http_status(:ok)
        address = restaurant.addresses.order(:created_at).first
        expect(address.street).to eq("123 Main St")
        expect(address.city).to eq("Test City")
        expect(address.postal_code).to eq("12345")
        expect(address.latitude).to be_within(0.01).of(40.7)
        expect(address.longitude).to be_within(0.01).of(-74.0)
      end

      it "rejects invalid coordinates" do
        mcp_call("update_restaurant", {
          restaurant: restaurant.id,
          latitude: "not a number"
        }, admin)

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("invalid_coordinate")
      end
    end

    context "as non-admin" do
      it "refuses the call" do
        mcp_call("update_restaurant", { restaurant: restaurant.id, name: "New" }, user)
        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
      end
    end
  end

  describe "set_restaurant_hours" do
    context "as admin" do
      it "replaces hours" do
        hours = [
          { day_of_week: 1, opens_at: "11:00", closes_at: "14:00" },
          { day_of_week: 1, opens_at: "17:00", closes_at: "21:00" },
          { day_of_week: 2, opens_at: "11:00", closes_at: "21:00" }
        ]

        mcp_call("set_restaurant_hours", {
          restaurant: restaurant.slug,
          hours: hours
        }, admin)

        expect(response).to have_http_status(:ok)
        restaurant.reload
        expect(restaurant.hours.count).to eq(3)
        monday_hours = restaurant.hours.where(day_of_week: 1).order(:opens_at)
        expect(monday_hours.size).to eq(2)
        expect(monday_hours.first.opens_at.strftime("%H:%M")).to eq("11:00")
        expect(monday_hours.last.opens_at.strftime("%H:%M")).to eq("17:00")
      end

      it "rejects invalid times" do
        mcp_call("set_restaurant_hours", {
          restaurant: restaurant.id,
          hours: [{ day_of_week: 1, opens_at: "25:99", closes_at: "14:00" }]
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("invalid_time_of_day")
      end
    end
  end

  describe "start_scan with base64" do
    context "as admin" do
      it "accepts base64_pdf" do
        pdf_content = "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\nxref\n0 3\ntrailer<</Size 3/Root 1 0 R>>\nstartxref\n103\n%%EOF"
        base64_pdf = Base64.strict_encode64(pdf_content)

        mcp_call("start_scan", {
          restaurant: restaurant.slug,
          base64_pdf: base64_pdf
        }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["scan_id"]).to be_present
        expect(content["ready"]).to be(false)
      end

      it "accepts base64_image" do
        # Minimal JPEG header
        jpeg_header = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
        base64_image = Base64.strict_encode64(jpeg_header)

        mcp_call("start_scan", {
          restaurant: restaurant.slug,
          base64_image: base64_image
        }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["scan_id"]).to be_present
      end

      it "rejects multiple sources" do
        mcp_call("start_scan", {
          restaurant: restaurant.slug,
          source_url: "https://example.com/menu",
          base64_pdf: Base64.strict_encode64("dummy")
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("multiple_sources")
      end

      it "rejects invalid base64" do
        mcp_call("start_scan", {
          restaurant: restaurant.slug,
          base64_pdf: "not valid base64!!!"
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("base64_decode_failed")
      end
    end
  end

  describe "get_scan" do
    let!(:run) { create(:ingestion_run, restaurant: restaurant, user: admin, status: "staged") }
    let!(:item1) do
      create(:ingestion_item, ingestion_run: run, name: "Burger", decision: "pending",
                              ingredients_payload: [{ slug: "beef", confidence: "confirmed", source: "ai" }])
    end
    let!(:item2) do
      create(:ingestion_item, ingestion_run: run, name: "Salad", decision: "accepted",
                              tags_payload: [{ slug: "vegetarian", confidence: "suggested", source: "ai" }])
    end
    let!(:beef) { create(:ingredient, slug: "beef", name: "Beef") }
    let!(:veg_tag) { create(:tag, slug: "vegetarian", name: "Vegetarian") }

    context "as admin" do
      it "returns scan status and items" do
        mcp_call("get_scan", { scan_id: run.id }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["ready"]).to be(true)
        expect(content["dish_count"]).to eq(2)
        expect(content["pending_count"]).to eq(1)
        expect(content["accepted_count"]).to eq(1)
        expect(content["items"].size).to eq(2)

        burger = content["items"].find { |i| i["name"].include?("Burger") }
        expect(burger["ingredients"][0]["slug"]).to eq("beef")
        expect(burger["ingredients"][0]["name"]).to eq("Beef")
        expect(burger["ingredients"][0]["confidence"]).to eq("confirmed")
      end
    end

    context "as non-admin non-owner" do
      let(:other_user) { create(:user) }

      it "refuses access to another user's scan" do
        mcp_call("get_scan", { scan_id: run.id }, other_user)
        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
      end
    end
  end

  describe "accept_items and reject_items" do
    let!(:run) { create(:ingestion_run, restaurant: restaurant, user: admin, status: "staged") }
    let!(:item1) { create(:ingestion_item, ingestion_run: run, name: "Item 1", decision: "pending") }
    let!(:item2) { create(:ingestion_item, ingestion_run: run, name: "Item 2", decision: "pending") }

    context "as admin" do
      it "accepts items" do
        mcp_call("accept_items", { scan_id: run.id, item_ids: [item1.id] }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["accepted"].size).to eq(1)
      end

      it "rejects items" do
        mcp_call("reject_items", { scan_id: run.id, item_ids: [item2.id] }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["rejected"].size).to eq(1)
        item2.reload
        expect(item2.decision).to eq("rejected")
      end

      it "respects publish threshold" do
        # Create enough items to test the 80% threshold
        8.times { |i| create(:ingestion_item, ingestion_run: run, name: "Item #{i + 3}", decision: "pending") }
        run.reload

        # Accept 80% (8 of 10 items)
        ids = run.ingestion_items.where(decision: "pending").limit(8).pluck(:id)
        mcp_call("accept_items", { scan_id: run.id, item_ids: ids }, admin)

        content = result_content
        expect(content["restaurant_published"]).to be(true)
        restaurant.reload
        expect(restaurant.status).to eq("published")
      end
    end
  end

  describe "list_restaurant_items" do
    let!(:item) { create(:item, restaurant: restaurant, name: "Test Item", status: "published") }
    let!(:removed_item) { create(:item, restaurant: restaurant, name: "Removed", status: "removed") }

    context "as admin" do
      it "lists all items including removed" do
        mcp_call("list_restaurant_items", { restaurant: restaurant.slug }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["count"]).to eq(2)
        expect(content["items"].map { |i| i["name"] }).to contain_exactly("Test Item", "Removed")
      end

      it "filters by status" do
        mcp_call("list_restaurant_items", { restaurant: restaurant.slug, status: "published" }, admin)

        content = result_content
        expect(content["count"]).to eq(1)
        expect(content["items"][0]["name"]).to eq("Test Item")
      end
    end
  end

  describe "update_published_item" do
    let!(:item) { create(:item, restaurant: restaurant, name: "Old Name", status: "published") }
    let!(:ing) { create(:ingredient, slug: "tomato", name: "Tomato") }

    context "as admin" do
      it "updates item fields" do
        mcp_call("update_published_item", {
          item_id: item.id,
          name: "New Name",
          description: "New description",
          ingredient_slugs: ["tomato"]
        }, admin)

        expect(response).to have_http_status(:ok)
        item.reload
        expect(item.name).to eq("New Name")
        expect(item.description).to eq("New description")
        expect(item.ingredients.pluck(:slug)).to eq(["tomato"])
      end

      it "sets status to removed" do
        mcp_call("update_published_item", {
          item_id: item.id,
          status: "removed"
        }, admin)

        item.reload
        expect(item.status).to eq("removed")
      end

      it "rejects unknown ingredient slugs" do
        mcp_call("update_published_item", {
          item_id: item.id,
          ingredient_slugs: ["nonexistent"]
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("Unknown")
      end

      it "validates price_cents as non-negative integer" do
        mcp_call("update_published_item", {
          item_id: item.id,
          variants: [{ size: "Large", price_cents: "not a number" }]
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("Invalid price_cents")
      end
    end
  end

  describe "set_restaurant_status" do
    context "as admin" do
      it "sets status to published" do
        mcp_call("set_restaurant_status", {
          restaurant: restaurant.slug,
          status: "published"
        }, admin)

        expect(response).to have_http_status(:ok)
        restaurant.reload
        expect(restaurant.status).to eq("published")
      end

      it "sets status to closed" do
        restaurant.update!(status: "published")
        mcp_call("set_restaurant_status", {
          restaurant: restaurant.slug,
          status: "closed"
        }, admin)

        restaurant.reload
        expect(restaurant.status).to eq("closed")
      end

      it "rejects invalid status" do
        mcp_call("set_restaurant_status", {
          restaurant: restaurant.id,
          status: "invalid"
        }, admin)

        result = JSON.parse(response.body)["result"]
        expect(result["isError"]).to be(true)
        expect(result.dig("content", 0, "text")).to include("Invalid status")
      end
    end
  end

  describe "create_restaurant" do
    let!(:existing) { create(:restaurant, name: "Cafe Mondo", city: city, status: "published") }

    context "as admin" do
      it "creates a new restaurant" do
        # Use the existing Restaurants::CreateRestaurant tool
        result = Tools::Restaurants::CreateRestaurant.call(
          server_context: { user_id: admin.id },
          name: "New Place",
          city_slug: city.slug,
          street: "123 Main St",
          postal_code: "12345"
        )

        content = result.to_h[:structuredContent]
        expect(content[:created]).to be(true)
        expect(content.dig(:restaurant, :name)).to eq("New Place")
        expect(content.dig(:restaurant, :status)).to eq("draft")
      end

      it "returns possible_duplicate without force" do
        result = Tools::Restaurants::CreateRestaurant.call(
          server_context: { user_id: admin.id },
          name: "Café Mondo",
          city_slug: city.slug
        )

        content = result.to_h[:structuredContent]
        expect(content[:created]).to be(false)
        expect(content[:reason]).to eq("possible_duplicate")
        expect(content[:possible_duplicates]).to be_present
        expect(content[:possible_duplicates].first[:name]).to eq("Cafe Mondo")
      end

      it "creates with force: true after reviewing duplicates" do
        result = Tools::Restaurants::CreateRestaurant.call(
          server_context: { user_id: admin.id },
          name: "Café Mondo",
          city_slug: city.slug,
          force: true
        )

        content = result.to_h[:structuredContent]
        expect(content[:created]).to be(true)
        expect(Restaurant.where(city: city).count).to eq(2)
      end

      it "rejects unknown city" do
        result = Tools::Restaurants::CreateRestaurant.call(
          server_context: { user_id: admin.id },
          name: "New Place",
          city_slug: "nonexistent"
        )

        content = result.to_h[:structuredContent]
        expect(content[:isError]).to be(true)
      end
    end

    context "as non-admin" do
      it "allows the call (audience is :user, not :admin)" do
        result = Tools::Restaurants::CreateRestaurant.call(
          server_context: { user_id: user.id },
          name: "New Place",
          city_slug: city.slug
        )

        content = result.to_h[:structuredContent]
        expect(content[:created]).to be(true)
      end
    end
  end

  describe "start_scan with source_text" do
    context "as admin" do
      it "accepts source_text input" do
        menu_text = "Burger - $10\nSalad - $8\nFries - $5"
        mcp_call("start_scan", {
          restaurant: restaurant.slug,
          source_text: menu_text
        }, admin)

        expect(response).to have_http_status(:ok)
        content = result_content
        expect(content["scan_id"]).to be_present
        expect(content["ready"]).to be(false)
      end
    end
  end
end
