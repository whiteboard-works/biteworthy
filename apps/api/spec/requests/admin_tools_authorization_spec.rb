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

  def jsonrpc_error?
    response_body = JSON.parse(response.body)
    response_body.key?("error")
  end

  def jsonrpc_error_message
    response_body = JSON.parse(response.body)
    response_body.dig("error", "message")
  end

  def jsonrpc_error_code
    response_body = JSON.parse(response.body)
    response_body.dig("error", "code")
  end

  def result_is_error?
    response_body = JSON.parse(response.body)
    return false unless response_body.key?("result")
    
    result = response_body["result"]
    result.is_a?(Hash) && result["isError"] == true
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
      let(:tool_name) { spec[:name] }
      let(:args_method) { spec[:args_method] }
      
      let(:args) do
        if args_method
          send(args_method)
        else
          spec[:args]
        end
      end

      context "as anonymous user" do
        it "refuses the call with tool not found or unauthorized" do
          # Force evaluation of let blocks before capturing counts
          restaurant
          scan
          item
          
          initial_restaurant_count = Restaurant.count
          initial_scan_count = IngestionRun.count

          mcp_call(tool_name, args, nil)

          expect(response).to have_http_status(:ok)
          # Should get JSON-RPC error (tool not found, since registry filters by audience)
          # OR a tool-level authorization error if the tool was somehow visible
          expect(jsonrpc_error? || result_is_error?).to be(true), 
            "Expected JSON-RPC error or tool error, got: #{response.body[0..500]}"

          if jsonrpc_error?
            # Tool not found is the expected case (registry filtered it out)
            # Invalid params can also happen if schema validation fails before tool execution
            error_msg = jsonrpc_error_message.to_s.downcase
            expect(error_msg).to match(/tool not found|not found|unauthorized|forbidden|invalid/i),
              "Expected blocking error, got: #{error_msg}"
          end

          # Verify no side effects
          expect(Restaurant.count).to eq(initial_restaurant_count)
          expect(IngestionRun.count).to eq(initial_scan_count)
        end
      end

      context "as non-admin user" do
        it "refuses the call with tool not found or forbidden" do
          # Force evaluation of let blocks before capturing counts
          restaurant
          scan
          item
          
          initial_restaurant_count = Restaurant.count
          initial_scan_count = IngestionRun.count

          mcp_call(tool_name, args, user)

          expect(response).to have_http_status(:ok)
          # Should get JSON-RPC error (tool not found, since registry filters by audience)
          # OR a tool-level forbidden error if the tool was somehow visible
          expect(jsonrpc_error? || result_is_error?).to be(true),
            "Expected JSON-RPC error or tool error, got: #{response.body[0..500]}"

          if jsonrpc_error?
            error_msg = jsonrpc_error_message.to_s.downcase
            expect(error_msg).to match(/tool not found|not found|forbidden|invalid/i),
              "Expected blocking error, got: #{error_msg}"
          end

          # Verify no side effects
          expect(Restaurant.count).to eq(initial_restaurant_count)
          expect(IngestionRun.count).to eq(initial_scan_count)
        end
      end

      context "as admin" do
        it "allows the call" do
          mcp_call(tool_name, args, admin)

          expect(response).to have_http_status(:ok)
          # The call should succeed (no JSON-RPC error, no tool error)
          expect(jsonrpc_error?).to be(false), 
            "Expected success, got JSON-RPC error: #{jsonrpc_error_message}"
          expect(result_is_error?).to be(false),
            "Expected success, got tool error in result"
        end
      end
    end
  end
end
