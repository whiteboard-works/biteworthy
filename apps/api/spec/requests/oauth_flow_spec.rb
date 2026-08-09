require "rails_helper"

# The whole OAuth 2.1 flow, end to end, because the pieces are only
# correct together: consent happens on one origin and the grant is issued
# on another, and what holds them together is a signed token bound to the
# exact request. Testing the halves separately would not catch a binding
# that does not bind.
RSpec.describe "OAuth 2.1 authorization", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  let(:client) do
    Doorkeeper::Application.create!(
      name: "Claude Desktop", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "discovery:read profile:read profile:write", confidential: false
    )
  end

  let(:verifier)  { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  def authorize_query(overrides = {})
    {
      client_id:             client.uid,
      redirect_uri:          client.redirect_uri,
      response_type:         "code",
      scope:                 "discovery:read profile:read",
      state:                 "xyz",
      code_challenge:        challenge,
      code_challenge_method: "S256"
    }.merge(overrides).to_query
  end

  def authorize_url(overrides = {})
    "http://www.example.com/oauth/authorize?#{authorize_query(overrides)}"
  end

  # Walk the browser half of the flow and hand back the resume URL the
  # web app would send the browser to.
  def approve(url = authorize_url)
    post "/api/v1/oauth/consent",
         params: { return_to: url }.to_json,
         headers: auth_headers_for(user).merge("Content-Type" => "application/json")
    response.parsed_body["redirect_to"]
  end

  describe "GET /oauth/authorize" do
    # Rails has no signed-in browser — the JWT lives in a cookie owned by
    # the web origin. So the first thing authorize does is leave.
    it "sends an unrecognised browser to the web app's consent page" do
      get "/oauth/authorize?#{authorize_query}"

      expect(response).to have_http_status(:redirect)
      expect(response.headers["Location"]).to start_with("#{Oauth::Handoff.web_origin}/oauth/consent")
      expect(Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["return_to"])
        .to include("client_id=#{client.uid}")
    end

    it "issues a code once the browser comes back with a handoff" do
      get URI.parse(approve).request_uri

      expect(response).to have_http_status(:redirect)
      location = URI.parse(response.headers["Location"])
      expect("#{location.scheme}://#{location.host}#{location.path}").to eq(client.redirect_uri)
      expect(Rack::Utils.parse_query(location.query)["code"]).to be_present
      expect(Rack::Utils.parse_query(location.query)["state"]).to eq("xyz")
    end

    # The property the whole handoff exists for. An approval is for the
    # request the person was shown and nothing else.
    it "refuses a handoff minted for a different request" do
      handoff = Rack::Utils.parse_query(URI.parse(approve).query)["handoff"]

      # Same handoff, wider scope than was ever displayed.
      get "/oauth/authorize?#{authorize_query(scope: 'users:write')}&handoff=#{Rack::Utils.escape(handoff)}"

      expect(response.headers["Location"]).to start_with(Oauth::Handoff.web_origin)
    end

    it "refuses a handoff pointed at a different redirect_uri" do
      handoff = Rack::Utils.parse_query(URI.parse(approve).query)["handoff"]

      get "/oauth/authorize?#{authorize_query(redirect_uri: 'https://evil.test/cb')}&handoff=#{Rack::Utils.escape(handoff)}"

      expect(response.headers["Location"]).to start_with(Oauth::Handoff.web_origin)
    end

    it "refuses a handoff that has aged out" do
      resume = approve

      travel_to(Oauth::Handoff::TTL.from_now + 1.minute) do
        get URI.parse(resume).request_uri
      end

      expect(response.headers["Location"]).to start_with(Oauth::Handoff.web_origin)
    end

    # PKCE is the only thing standing between a stolen code and a token
    # for a client that cannot hold a secret.
    it "will not start a flow without a code challenge" do
      get URI.parse(approve(authorize_url(code_challenge: nil, code_challenge_method: nil))).request_uri

      expect(response.headers["Location"]).to include("error=invalid_request")
    end

    it "will not accept a plain code challenge" do
      get URI.parse(approve(authorize_url(code_challenge_method: "plain"))).request_uri

      expect(response.headers["Location"]).to include("error=invalid_code_challenge_method")
    end
  end

  describe "POST /oauth/token" do
    let(:code) { Rack::Utils.parse_query(URI.parse(response_location_after_approve).query)["code"] }

    def response_location_after_approve
      get URI.parse(approve).request_uri
      response.headers["Location"]
    end

    it "exchanges a code plus the verifier for an access token" do
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: client.redirect_uri,
        client_id: client.uid, code_verifier: verifier
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["access_token"]).to be_present
      expect(response.parsed_body["refresh_token"]).to be_present
      expect(response.parsed_body["scope"]).to eq("discovery:read profile:read")
    end

    it "refuses the wrong verifier" do
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: client.redirect_uri,
        client_id: client.uid, code_verifier: "b" * 64
      }

      expect(response).to have_http_status(:bad_request)
    end

    # Hashed at rest for the same reason McpToken is: a leaked database
    # must not be a leaked set of working credentials.
    it "does not store the token it just handed out" do
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: client.redirect_uri,
        client_id: client.uid, code_verifier: verifier
      }
      secret = response.parsed_body["access_token"]

      expect(Doorkeeper::AccessToken.pluck(:token)).not_to include(secret)
      expect(Doorkeeper::AccessToken.by_token(secret)).to be_present
    end
  end

  describe "the token at the MCP door" do
    let(:secret) do
      get URI.parse(approve).request_uri
      code = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["code"]
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: client.redirect_uri,
        client_id: client.uid, code_verifier: verifier
      }
      response.parsed_body["access_token"]
    end

    def call_tool(name, arguments = {}, token: secret)
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                     params: { name: name, arguments: arguments } }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                      "Authorization" => "Bearer #{token}" }
      JSON.parse(response.body)
    end

    it "authenticates as the person who approved it" do
      body = call_tool("get_profile")

      expect(response).to have_http_status(:ok)
      expect(body.dig("result", "isError")).to be_falsey
    end

    # The scopes the person actually saw are the scopes the token carries.
    # Read on a domain was approved; write on the same domain was not, and
    # that is exactly the line a consent screen is for.
    # The catalogue this grant sees is filtered to the scopes it holds, so
    # the write tool is not merely refused — it was never offered, and the
    # refusal reads as "no such tool". What a consent screen has to
    # guarantee is that the unapproved write does not happen.
    it "cannot reach a tool outside the scopes that were approved" do
      body = call_tool("update_avoid_lists", { add_ingredients: ["dairy"] })

      expect(body["error"]).to be_present
      expect(user.reload.profile&.avoid_ingredient_ids).to be_blank
    end

    it "stops working once revoked" do
      Doorkeeper::AccessToken.by_token(secret).update!(revoked_at: Time.current)

      call_tool("get_profile")

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # A client that has never been configured has to be able to find its way
  # in from a 401 alone.
  describe "discovery" do
    it "points a rejected caller at the protected-resource document" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                   headers: { "Content-Type" => "application/json",
                              "Accept" => "application/json, text/event-stream",
                              "Authorization" => "Bearer not-a-real-token" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"])
        .to include('resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp')
    end

    it "names the authorization server that guards the MCP resource" do
      get "/.well-known/oauth-protected-resource/mcp"

      expect(response.parsed_body["resource"]).to eq("http://www.example.com/mcp")
      expect(response.parsed_body["authorization_servers"]).to eq(["http://www.example.com"])
    end

    it "advertises endpoints, S256 only, and every grantable scope" do
      get "/.well-known/oauth-authorization-server"

      body = response.parsed_body
      expect(body["authorization_endpoint"]).to eq("http://www.example.com/oauth/authorize")
      expect(body["code_challenge_methods_supported"]).to eq(["S256"])
      expect(body["scopes_supported"]).to match_array(Tools::Scopes.available)
    end
  end
end
