require "rails_helper"

# Menus, sections, address and hours — the restaurant scaffolding an
# admin reorganizes after a scan dumps everything into one bucket.
# The rule worth protecting: restructuring must never destroy dishes.
# A deleted section unsections its items; a deleted menu takes its
# sections but leaves the items standing.
RSpec.describe "Admin restaurant structure", type: :request do
  let(:admin)      { create(:user, :admin) }
  let(:restaurant) { create(:restaurant, :published) }

  def json_headers
    auth_headers_for(admin).merge("Content-Type" => "application/json")
  end

  describe "menus + sections" do
    it "creates a menu, adds a section, and lists the tree" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/menus",
           params: { name: "Dinner", position: 1 }.to_json, headers: json_headers
      expect(response).to have_http_status(:created)
      menu_id = response.parsed_body["id"]

      post "/api/v1/admin/menus/#{menu_id}/menu_sections",
           params: { name: "Tacos", position: 0 }.to_json, headers: json_headers
      expect(response).to have_http_status(:created)

      get "/api/v1/admin/restaurants/#{restaurant.id}/menus", headers: json_headers
      tree = response.parsed_body["menus"]
      expect(tree.map { |m| m["name"] }).to include("Dinner")
      dinner = tree.find { |m| m["id"] == menu_id }
      expect(dinner["sections"].map { |s| s["name"] }).to eq(["Tacos"])
      expect(dinner["sections"].first["items_count"]).to eq(0)
    end

    it "renames and repositions a menu" do
      menu = create(:menu, restaurant: restaurant, name: "Old", position: 0)

      patch "/api/v1/admin/menus/#{menu.id}",
            params: { name: "New", position: 3 }.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(menu.reload).to have_attributes(name: "New", position: 3)
    end

    # Reorganizing the menu must never cost the restaurant its dishes.
    it "deleting a section unsections its items instead of deleting them" do
      menu    = create(:menu, restaurant: restaurant)
      section = create(:menu_section, menu: menu)
      item    = create(:item, restaurant: restaurant, menu_section: section)

      delete "/api/v1/admin/menu_sections/#{section.id}", headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("deleted" => true, "items_unsectioned" => 1)
      expect(item.reload).to be_persisted
      expect(item.menu_section_id).to be_nil
    end

    it "deleting a menu takes its sections but leaves the items" do
      menu    = create(:menu, restaurant: restaurant)
      section = create(:menu_section, menu: menu)
      item    = create(:item, restaurant: restaurant, menu_section: section)

      delete "/api/v1/admin/menus/#{menu.id}", headers: json_headers

      expect(response).to have_http_status(:no_content)
      expect(MenuSection.exists?(section.id)).to be false
      expect(item.reload.menu_section_id).to be_nil
    end

    it "404s non-admins" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/menus",
           params: { name: "Nope" }.to_json,
           headers: auth_headers_for(create(:user)).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "address" do
    it "creates on first write and updates in place after" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/address",
          params: { street: "123 Main St", city: "Durango", region: "CO",
                    postal_code: "81301" }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["address"]).to include("street" => "123 Main St", "city" => "Durango")
      expect(restaurant.reload.addresses.count).to eq(1)

      put "/api/v1/admin/restaurants/#{restaurant.id}/address",
          params: { street: "456 Side St" }.to_json, headers: json_headers

      expect(restaurant.reload.addresses.count).to eq(1)
      expect(restaurant.addresses.first.street).to eq("456 Side St")
    end
  end

  describe "hours" do
    it "replaces the whole week and renders times as HH:MM" do
      restaurant.hours.create!(day_of_week: 0, opens_at: "08:00", closes_at: "14:00")

      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: [
            { day_of_week: 1, opens_at: "11:00", closes_at: "21:00" },
            # No times = closed that day, which the nullable columns exist for.
            { day_of_week: 2 }
          ] }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body["hours"]
      expect(rows.map { |h| h["day_of_week"] }).to eq([1, 2])
      expect(rows.first).to include("opens_at" => "11:00", "closes_at" => "21:00")
      expect(rows.last).to include("opens_at" => nil, "closes_at" => nil)
      # Monday's replacement wiped Sunday's old row — a full-week write.
      expect(restaurant.reload.hours.pluck(:day_of_week)).to contain_exactly(1, 2)
    end

    it "422s an out-of-range day without touching the stored week" do
      restaurant.hours.create!(day_of_week: 3, opens_at: "09:00")

      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: [{ day_of_week: 9, opens_at: "10:00" }] }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "invalid_day_of_week", "values" => [9])
      expect(restaurant.reload.hours.pluck(:day_of_week)).to eq([3])
    end

    it "422s a non-array payload" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: "closed" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("hours_must_be_an_array")
    end
  end

  it "exposes address + hours together on the place endpoint" do
    restaurant.hours.create!(day_of_week: 5, opens_at: "17:00", closes_at: "23:00")
    restaurant.addresses.create!(street: "1 Elm", city: "Durango")

    get "/api/v1/admin/restaurants/#{restaurant.id}/place", headers: json_headers

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["address"]).to include("street" => "1 Elm")
    expect(body["hours"].first).to include("day_of_week" => 5, "opens_at" => "17:00")
  end
end
