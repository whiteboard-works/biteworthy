require "rails_helper"

# The MCP transport contract: JSON-RPC in, JSON-RPC out, and — the part
# that matters for safety — a tool list that differs by who is asking.
RSpec.describe "POST /mcp", type: :request do
  let(:user)  { create(:user) }
  let(:admin) { create(:user, is_admin: true) }

  def rpc(method, params = {}, headers: {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }.merge(headers)
    response.parsed_body
  end

  def tool_names(headers: {})
    rpc("tools/list", {}, headers: headers).dig("result", "tools").map { |t| t["name"] }
  end

  describe "initialize" do
    it "advertises the server and its instructions" do
      body = rpc("initialize", {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "rspec", version: "1.0" }
      })

      expect(response).to have_http_status(:ok)
      expect(body.dig("result", "serverInfo", "name")).to eq("biteworthy")
      expect(body.dig("result", "instructions")).to include("untrusted")
    end
  end

  describe "tools/list" do
    it "gives anonymous callers the public discovery tools only" do
      names = tool_names

      expect(names).to include("get_menu", "search_restaurants", "search_taxonomy")
      expect(names).not_to include("get_profile", "update_avoid_lists")
    end

    # A listed-but-forbidden tool would still leak that the capability
    # exists and would burn the model's turns discovering it can't call it.
    it "adds the profile tools once a caller is signed in" do
      names = tool_names(headers: auth_headers_for(user))

      expect(names).to include("get_profile", "update_avoid_lists", "set_strictness")
    end

    it "hides admin-only tools from non-admins" do
      admin_only = Tools::Registry.all.select { |t| t.audience == :admin }.map(&:name_value)
      skip "no admin tools registered yet" if admin_only.empty?

      expect(tool_names(headers: auth_headers_for(user))).not_to include(*admin_only)
      expect(tool_names(headers: auth_headers_for(admin))).to include(*admin_only)
    end
  end

  describe "authentication" do
    it "treats a missing Authorization header as anonymous, not an error" do
      expect(tool_names).to be_present
      expect(response).to have_http_status(:ok)
    end

    # Silently downgrading a stale token to anonymous would show the caller
    # someone else's (empty) filter without telling them they're logged out.
    it "401s a bad token rather than falling back to anonymous" do
      rpc("tools/list", {}, headers: { "Authorization" => "Bearer not-a-real-token" })

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include("Bearer")
    end
  end

  describe "tools/call" do
    let!(:city)       { create(:city, slug: "durango") }
    let!(:restaurant) { create(:restaurant, :published, city: city, name: "Ninis Taqueria", slug: "ninis") }

    it "runs a public tool anonymously" do
      body = rpc("tools/call", { name: "get_restaurant", arguments: { restaurant: "ninis" } })

      expect(body.dig("result", "isError")).to be_falsey
      expect(body.dig("result", "structuredContent", "name")).to eq("Ninis Taqueria")
    end

    # The tool was never listed for this caller, so the transport rejects
    # the name outright. The audience check inside Tools::Base is the
    # second line of defence for callers working from a stale tool list —
    # see spec/services/tools/base_spec.rb.
    it "refuses a tool the caller was never offered" do
      body = rpc("tools/call", { name: "get_profile", arguments: {} })

      expect(body.dig("result", "structuredContent")).to be_nil
      expect(body.dig("error", "code")).to eq(-32_602) # JSON-RPC invalid params
    end

    it "reports unknown arguments through the schema rather than 500ing" do
      body = rpc("tools/call", { name: "get_menu", arguments: {} }, headers: auth_headers_for(user))

      expect(body.dig("result", "isError")).to be(true)
      expect(body.dig("result", "content", 0, "text")).to match(/restaurant/i)
    end
  end

  # The tool map is served as a resource so a client that reads resources
  # learns how the tools compose without spending a turn on a tool call.
  describe "resources" do
    it "advertises the topology" do
      body = rpc("resources/list")

      expect(body.dig("result", "resources").map { |r| r["uri"] }).to include("biteworthy://topology")
    end

    it "reads it as markdown, scoped to the caller" do
      body = rpc("resources/read", { uri: "biteworthy://topology" })

      text = body.dig("result", "contents", 0, "text")
      expect(text).to include("## Workflows")
      expect(text).not_to include("moderate_review")
    end

    it "includes the admin workflows for an admin" do
      body = rpc("resources/read", { uri: "biteworthy://topology" }, headers: auth_headers_for(admin))

      expect(body.dig("result", "contents", 0, "text")).to include("moderate_review")
    end
  end
end
