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
  ADMIN_TOOLS = {
    "find_restaurants" => {},
    "update_restaurant" => proc { { restaurant: restaurant.id, name: "Updated Name" } },
    "set_restaurant_hours" => proc { { restaurant: restaurant.id, hours: [] } },
    "start_scan" => proc { { restaurant: restaurant.id, source_text: "Menu text" } },
    "get_scan" => proc { { scan_id: scan.id } },
    "accept_items" => proc { { scan_id: scan.id, all: true } },
    "reject_items" => proc { { scan_id: scan.id, all: true } },
    "list_restaurant_items" => proc { { restaurant: restaurant.id } },
    "update_published_item" => proc { { item_id: item.id, name: "Updated Item" } },
    "set_restaurant_status" => proc { { restaurant: restaurant.id, status: "draft" } }
  }.freeze

  ADMIN_TOOLS.each do |tool_name, args_proc|
    describe tool_name do
      let(:args) { args_proc.is_a?(Proc) ? args_proc.call : args_proc }

      context "as anonymous user" do
        it "refuses the call with unauthorized" do
          initial_restaurant_count = Restaurant.count
          initial_scan_count = IngestionRun.count

          mcp_call(tool_name, args, nil)

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

          mcp_call(tool_name, args, user)

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
          mcp_call(tool_name, args, admin)

          expect(response).to have_http_status(:ok)
          # The call should succeed (isError should be false or nil)
          expect(result_is_error?).to be_falsey
        end
      end
    end
  end
end
