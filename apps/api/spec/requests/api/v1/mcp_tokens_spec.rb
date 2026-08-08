require "rails_helper"

# Connecting Claude Code should not require a shell on the box. The rake
# task works for whoever has one; this is for everyone else.
RSpec.describe "Api::V1::McpTokens", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "POST /api/v1/mcp_tokens" do
    # The one and only time this value exists anywhere it can be read.
    it "returns the secret once, on creation" do
      post "/api/v1/mcp_tokens",
           params: { name: "Claude Code", scopes: ["discovery:read"] }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["secret"]).to start_with(McpToken::PREFIX)
      expect(response.parsed_body["scopes"]).to eq(["discovery:read"])
    end

    it "refuses a scope that means nothing" do
      post "/api/v1/mcp_tokens",
           params: { name: "x", scopes: ["menus:teleport"] }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("menus:teleport")
    end

    it "insists on a name, so a list of tokens stays legible" do
      post "/api/v1/mcp_tokens",
           params: { name: "  " }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "caps how many can be live at once" do
      McpToken::MAX_ACTIVE.times { |i| McpToken.issue!(user: user, name: "t#{i}") }

      post "/api/v1/mcp_tokens",
           params: { name: "one too many" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/mcp_tokens" do
    # Nothing stored can reproduce the secret, so there is no endpoint
    # that could return it — including this one.
    it "lists active tokens without their secrets" do
      McpToken.issue!(user: user, name: "Claude Code", scopes: ["discovery:read"])

      get "/api/v1/mcp_tokens", headers: headers

      token = response.parsed_body["tokens"].first
      expect(token["name"]).to eq("Claude Code")
      expect(token).not_to have_key("secret")
      expect(response.body).not_to include(McpToken::PREFIX)
    end

    it "offers the grantable scopes so a client need not hardcode them" do
      get "/api/v1/mcp_tokens", headers: headers

      expect(response.parsed_body["scopes"]).to include("discovery:read", "profile:write")
    end

    it "leaves out revoked ones" do
      token, = McpToken.issue!(user: user, name: "old laptop")
      token.revoke!

      get "/api/v1/mcp_tokens", headers: headers

      expect(response.parsed_body["tokens"]).to be_empty
    end

    it "never shows another account's tokens" do
      McpToken.issue!(user: create(:user), name: "someone else's")

      get "/api/v1/mcp_tokens", headers: headers

      expect(response.parsed_body["tokens"]).to be_empty
    end
  end

  describe "DELETE /api/v1/mcp_tokens/:id" do
    it "revokes the caller's own token" do
      token, secret = McpToken.issue!(user: user, name: "old laptop")

      delete "/api/v1/mcp_tokens/#{token.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(McpToken.authenticate(secret)).to be_nil
    end

    # Revoking by id must not become a way to disable someone else's
    # integration.
    it "404s another account's token and leaves it working" do
      token, secret = McpToken.issue!(user: create(:user), name: "theirs")

      delete "/api/v1/mcp_tokens/#{token.id}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(McpToken.authenticate(secret)).to eq(token)
    end
  end

  it "requires a signed-in caller" do
    get "/api/v1/mcp_tokens"

    expect(response).to have_http_status(:unauthorized)
  end
end
