require "rails_helper"

# What the consent page in apps/web reads and posts. The screen decides
# nothing on its own — every rule that matters is enforced here, because a
# page is not a security boundary.
RSpec.describe "Api::V1::OauthConsents", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

  let(:client) do
    Doorkeeper::Application.create!(
      name: "Claude Desktop", redirect_uri: "https://claude.ai/cb",
      scopes: "discovery:read profile:write", confidential: false
    )
  end

  def authorize_url(overrides = {})
    query = {
      client_id: client.uid, redirect_uri: client.redirect_uri, response_type: "code",
      scope: "discovery:read profile:write", state: "xyz",
      code_challenge: "c" * 43, code_challenge_method: "S256"
    }.merge(overrides).compact.to_query
    "http://www.example.com/oauth/authorize?#{query}"
  end

  describe "GET /api/v1/oauth/consent" do
    # A scope string is not consent. "profile:write" tells nobody what
    # they are agreeing to; a sentence does.
    it "describes the client and each scope in words" do
      get "/api/v1/oauth/consent", params: { return_to: authorize_url }, headers: headers

      body = response.parsed_body
      expect(body.dig("client", "name")).to eq("Claude Desktop")
      expect(body["scopes"].map { |s| s["name"] }).to eq(["discovery:read", "profile:write"])
      expect(body["scopes"].last["description"]).to match(/avoid lists/)
    end

    # The screen shows where approval actually sends you, so a client
    # calling itself "Biteworthy" cannot hide its destination.
    it "returns the redirect the client will be sent to" do
      get "/api/v1/oauth/consent", params: { return_to: authorize_url }, headers: headers

      expect(response.parsed_body["redirect_uri"]).to eq(client.redirect_uri)
    end

    it "404s a client that was never registered" do
      get "/api/v1/oauth/consent", params: { return_to: authorize_url(client_id: "nope") }, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    # Minting is only safe because the digest is over an authorize URL we
    # recognise. A return_to pointing anywhere else would make this an
    # oracle that signs whatever it is handed.
    it "refuses a return_to that is not our authorize endpoint" do
      get "/api/v1/oauth/consent",
          params: { return_to: "https://evil.test/oauth/authorize?client_id=x" }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires a signed-in caller" do
      get "/api/v1/oauth/consent", params: { return_to: authorize_url }

      expect(response).to have_http_status(:unauthorized)
    end

    # The page sends a denial straight back to this URI, and displays it
    # as where approval leads. Letting the request name it freely would
    # be an open redirect and a lie at the same time.
    it "refuses a redirect_uri the client never registered" do
      get "/api/v1/oauth/consent",
          params: { return_to: authorize_url(redirect_uri: "https://evil.test/cb") }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # RFC 8707. A token minted here is for this resource; a client asking
    # for one audienced elsewhere is asking the wrong server.
    it "refuses a resource indicator naming a different audience" do
      get "/api/v1/oauth/consent",
          params: { return_to: authorize_url(resource: "https://someone-else.test/mcp") }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "accepts a resource indicator naming this MCP server" do
      get "/api/v1/oauth/consent",
          params: { return_to: authorize_url(resource: "http://www.example.com/mcp") }, headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/oauth/consent" do
    it "hands back the URL to send the browser to, carrying the handoff" do
      post "/api/v1/oauth/consent", params: { return_to: authorize_url }.to_json, headers: headers

      resume = response.parsed_body["redirect_to"]
      expect(resume).to start_with("http://www.example.com/oauth/authorize?")
      expect(Rack::Utils.parse_query(URI.parse(resume).query)["handoff"]).to be_present
    end

    it "requires a signed-in caller" do
      post "/api/v1/oauth/consent", params: { return_to: authorize_url }.to_json,
                                    headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
