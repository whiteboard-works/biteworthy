# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin tools authorization" do
  let(:admin) { create(:user, is_admin: true) }
  let(:user) { create(:user, is_admin: false) }
  let(:city) { create(:city, slug: "test-city") }
  let(:restaurant) { create(:restaurant, city: city, status: "draft") }
  let(:item) { create(:item, restaurant: restaurant, status: "published") }
  let(:scan) { create(:ingestion_run, restaurant: restaurant, user: admin, status: "staged") }

  def mcp_call(tool_name, args, auth_user)
    headers = { "Content-Type": "application/json" }
    headers["Authorization"] = "Bearer #{jwt_for(auth_user)}" if auth_user

    post "/mcp", params: {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: tool_name, arguments: args }
    }.to_json, headers: headers
  end

  def jwt_for(user)
    Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
  end

  def result_is_error?
    JSON.parse(response.body).dig("result", "isError")
  end

  def result_code
    response_body = JSON.parse(response.body)
    return nil unless response_body["result"].is_a?(Hash)

    content = response_body.dig("result", "content")
    return nil unless content.is_a?(Array) && content[0].is_a?(Hash)

    text = content[0]["text"]
    return nil unless text.is_a?(String)

    # Parse the error response to extract the code
    begin
      error_data = JSON.parse(text)
      error_data["code"] if error_data.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end

  # Map each admin tool to minimal valid arguments
  # Procs are evaluated inside the test context where lets are available
  ADMIN_TOOLS_SPECS = [
    { name: "find_restaurants", args: {} },
    { name: "update_restaurant", args_method: :update_restaurant_args },
    { name: "set_restaurant_hours", args_method: :set_restaurant_hours_args },
    { name: "start_scan", args_method: :start_scan_args },
    { name: "get_scan", args_method: :get_scan_args },
    { name: "accept_items", args_method: :accept_items_args },
    { name: "reject_items", args_method: :reject_items_args },
    { name: "list_restaurant_items", args_method: :list_restaurant_items_args },
    { name: "update_published_item", args_method: :update_published_item_args },
    { name: "set_restaurant_status", args_method: :set_restaurant_status_args }
  ].freeze

  def update_restaurant_args
    { restaurant: restaurant.id, name: "Updated Name" }
  end

  def set_restaurant_hours_args
    { restaurant: restaurant.id, hours: [] }
  end

  def start_scan_args
    { restaurant: restaurant.id, source_text: "Menu text" }
  end

  def get_scan_args
    { scan_id: scan.id }
  end

  def accept_items_args
    { scan_id: scan.id, all: true }
  end

  def reject_items_args
    { scan_id: scan.id, item_ids: [] }
  end

  def list_restaurant_items_args
    { restaurant: restaurant.id }
  end

  def update_published_item_args
    { item_id: item.id, name: "Updated Item" }
  end

  def set_restaurant_status_args
    { restaurant: restaurant.id, status: "draft" }
  end

  ADMIN_TOOLS_SPECS.each do |spec|
    describe spec[:name] do
      let(:args) do
        if spec[:args_method]
          send(spec[:args_method])
        else
          spec[:args]
        end
      end

      context "as anonymous user" do
        it "refuses the call with unauthorized" do
          initial_restaurant_count = Restaurant.count
          initial_scan_count = IngestionRun.count

          mcp_call(spec[:name], args, nil)

          expect(response).to have_http_status(:ok)
          expect(result_is_error?).to be(true)
          code = result_code
          expect(["unauthorized", "forbidden"]).to include(code), 
            "Expected unauthorized or forbidden, got: #{code}"

          # Verify no side effects
          expect(Restaurant.count).to eq(initial_restaurant_count)
          expect(IngestionRun.count).to eq(initial_scan_count)
        end
      end

      context "as non-admin user" do
        it "refuses the call with forbidden" do
          initial_restaurant_count = Restaurant.count
          initial_scan_count = IngestionRun.count

          mcp_call(spec[:name], args, user)

          expect(response).to have_http_status(:ok)
          expect(result_is_error?).to be(true)
          expect(result_code).to eq("forbidden")

          # Verify no side effects
          expect(Restaurant.count).to eq(initial_restaurant_count)
          expect(IngestionRun.count).to eq(initial_scan_count)
        end
      end

      context "as admin" do
        it "allows the call" do
          mcp_call(spec[:name], args, admin)

          expect(response).to have_http_status(:ok)
          # The call should succeed (isError should be false or nil)
          expect(result_is_error?).to be_falsey
        end
      end
    end
  end
end
