require "rails_helper"

# Approving an OAuth grant was a one-way door until this shipped: M8 skips
# doorkeeper's own :authorized_applications UI, and the refresh chain
# behind a two-hour access token has no expiry, so nothing short of a
# Rails console could end a connection. These are the properties that make
# "disconnect" mean it.
RSpec.describe "Api::V1::ConnectedApps", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  let(:client) do
    Doorkeeper::Application.create!(
      name: "Claude Desktop", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "discovery:read profile:read profile:write", confidential: false
    )
  end

  def grant!(to: user, app: client, scopes: "discovery:read profile:read", expires_in: 2.hours.to_i)
    Doorkeeper::AccessToken.create!(
      application: app, resource_owner_id: to.id, scopes: scopes,
      expires_in: expires_in, use_refresh_token: true
    )
  end

  def apps
    get "/api/v1/connected_apps", headers: auth_headers_for(user)
    response.parsed_body["apps"]
  end

  def tools_list(secret)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Authorization" => "Bearer #{secret}", "CONTENT_TYPE" => "application/json" }
    response.status
  end

  describe "GET /api/v1/connected_apps" do
    it "requires a signed-in caller" do
      get "/api/v1/connected_apps"

      expect(response).to have_http_status(:unauthorized)
    end

    it "is empty for someone who has connected nothing" do
      expect(apps).to eq([])
    end

    it "names the app and what it was granted" do
      grant!

      expect(apps.length).to eq(1)
      expect(apps.first["name"]).to eq("Claude Desktop")
      expect(apps.first["scopes"]).to eq(["discovery:read", "profile:read"])
    end

    # The list is what someone decides to revoke from, so it has to say
    # what they agreed to in the words they agreed to it in — the same
    # sentences `Tools::Scopes.describe` renders on the consent screen.
    it "renders each scope as the sentence consent showed" do
      grant!

      details = apps.first["scope_details"]
      expect(details.map { |d| d["scope"] }).to eq(["discovery:read", "profile:read"])
      expect(details.map { |d| d["description"] }).to all(be_present)
      expect(details.map { |d| d["description"] }).to eq(
        ["discovery:read", "profile:read"].map { |s| Tools::Scopes.describe(s) }
      )
    end

    # The trap this endpoint exists to avoid. An access token lives two
    # hours; the grant behind it lives until revoked, because the client
    # refreshes. A list filtered on "unexpired" would go empty two hours
    # after every connection and tell people they had disconnected an app
    # that was still reading their profile.
    it "still lists an app whose access token has expired but was never revoked" do
      grant!(expires_in: 1.hour.to_i)
      travel_to(3.hours.from_now) { expect(apps.length).to eq(1) }
    end

    it "leaves out a connection that was already revoked" do
      grant!.revoke

      expect(apps).to eq([])
    end

    it "never shows someone else's connections" do
      grant!(to: other)

      expect(apps).to eq([])
    end

    # Every refresh writes a new token row for the same application.
    it "collapses an app's refresh history into one entry" do
      grant!
      grant!(scopes: "discovery:read")

      expect(apps.length).to eq(1)
      expect(apps.first["scopes"]).to eq(["discovery:read", "profile:read"])
    end
  end

  describe "DELETE /api/v1/connected_apps/:id" do
    it "requires a signed-in caller" do
      delete "/api/v1/connected_apps/#{client.id}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "ends every live token the app holds for this person" do
      first  = grant!
      second = grant!

      delete "/api/v1/connected_apps/#{client.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:no_content)
      expect(first.reload.revoked_at).to be_present
      expect(second.reload.revoked_at).to be_present
      expect(apps).to eq([])
    end

    # A client holding an unexchanged authorization code must not be able
    # to walk back in a second after being cut off.
    it "ends an unexchanged authorization code too" do
      grant!
      code = Doorkeeper::AccessGrant.create!(
        application: client, resource_owner_id: user.id, redirect_uri: client.redirect_uri,
        expires_in: 600, scopes: "discovery:read"
      )

      delete "/api/v1/connected_apps/#{client.id}", headers: auth_headers_for(user)

      expect(code.reload.revoked_at).to be_present
    end

    # The token is what a revoked client still holds, so the assertion
    # that matters is that the token stops working — not that a column
    # changed. Asserted against the same secret before and after, because
    # secrets are hashed at rest: a `plaintext_token` that came back nil
    # would 401 on its own and this would pass without revoking anything.
    it "stops the app's token from reaching the MCP door" do
      secret = grant!.plaintext_token

      expect(tools_list(secret)).to eq(200)

      delete "/api/v1/connected_apps/#{client.id}", headers: auth_headers_for(user)

      expect(tools_list(secret)).to eq(401)
    end

    # Revoking is per-app, not "sign me out of everything".
    it "leaves the person's other connections alone" do
      keep = Doorkeeper::Application.create!(
        name: "Claude Code", redirect_uri: "http://127.0.0.1:8976/callback",
        scopes: "discovery:read", confidential: false
      )
      grant!
      survivor = grant!(app: keep, scopes: "discovery:read")

      delete "/api/v1/connected_apps/#{client.id}", headers: auth_headers_for(user)

      expect(survivor.reload.revoked_at).to be_nil
      expect(apps.map { |a| a["name"] }).to eq(["Claude Code"])
    end

    # Someone else's grant on the same application must read as absent,
    # not as forbidden — an id that answers differently is an id that
    # tells you whose it is.
    it "refuses to revoke a connection belonging to someone else" do
      theirs = grant!(to: other)

      delete "/api/v1/connected_apps/#{client.id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.revoked_at).to be_nil
    end

    it "answers not-found for an unknown id rather than erroring" do
      delete "/api/v1/connected_apps/#{SecureRandom.uuid}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end
  end
end
