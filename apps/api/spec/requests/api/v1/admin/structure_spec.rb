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

  describe "sections + menus reject junk instead of swallowing it" do
    it "422s a nameless section rather than hitting the NOT NULL constraint" do
      menu = create(:menu, restaurant: restaurant)

      post "/api/v1/admin/menus/#{menu.id}/menu_sections",
           params: { description: "no name" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(menu.reload.menu_sections).to be_empty
    end

    it "422s a non-string name instead of dropping it behind a 201" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/menus",
           params: { name: 42 }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("invalid_name")
      expect(restaurant.reload.menus).to be_empty
    end

    it "422s a non-numeric position instead of storing 0" do
      post "/api/v1/admin/restaurants/#{restaurant.id}/menus",
           params: { name: "Brunch", position: "abc" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("invalid_position")
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

    # An unparseable decimal casts to 0.0 — Null Island, which the
    # public restaurant payload then serves.
    it "422s a non-numeric coordinate instead of relocating to 0,0" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/address",
          params: { street: "1 Elm", latitude: "abc" }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("error" => "invalid_coordinate")
      expect(restaurant.reload.addresses).to be_empty
    end

    it "accepts real coordinates" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/address",
          params: { street: "1 Elm", latitude: 37.2753, longitude: -107.8801 }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["address"]).to include("latitude" => 37.2753)
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
      expect(response.parsed_body).to eq("error" => "invalid_day_of_week", "values" => ["9"])
      expect(restaurant.reload.hours.pluck(:day_of_week)).to eq([3])
    end

    # Rails would cast "monday".to_i to 0 — publishing Sunday hours
    # under a 200 while wiping the rest of the week.
    it "422s a non-numeric day instead of silently storing Sunday" do
      restaurant.hours.create!(day_of_week: 3, opens_at: "09:00")

      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: [{ day_of_week: "monday", opens_at: "11:00" }] }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "invalid_day_of_week", "values" => ["monday"])
      expect(restaurant.reload.hours.pluck(:day_of_week)).to eq([3])
    end

    # An unparseable time casts to nil, and nil is this API's encoding
    # for "closed" — a typo would advertise the restaurant as shut.
    it "422s an unparseable time instead of marking the day closed" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: [{ day_of_week: 1, opens_at: "25:99" }] }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "invalid_time_of_day", "values" => ["25:99"])
      expect(restaurant.reload.hours).to be_empty
    end

    it "422s a non-object row rather than 500ing" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: ["closed"] }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("hour_rows_must_be_objects")
    end

    it "422s duplicate days — a week has one row per day" do
      put "/api/v1/admin/restaurants/#{restaurant.id}/hours",
          params: { hours: [
            { day_of_week: 1, opens_at: "09:00" },
            { day_of_week: 1, opens_at: "17:00" }
          ] }.to_json,
          headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("duplicate_day_of_week")
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
