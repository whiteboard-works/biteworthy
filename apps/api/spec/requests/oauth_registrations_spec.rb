require "rails_helper"

# RFC 7591. A client in a connector directory has nobody to email for a
# client id, so it registers itself — which makes this the one endpoint an
# anonymous caller can create rows through. What keeps that safe is that a
# client id grants nothing: every authorization still goes through a person
# approving named scopes.
RSpec.describe "OAuth dynamic client registration", type: :request do
  def register(body)
    post "/oauth/register", params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  it "registers a public client and returns its id" do
    register(redirect_uris: ["https://claude.ai/api/mcp/auth_callback"], client_name: "Claude")

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["client_id"]).to be_present
    expect(body["token_endpoint_auth_method"]).to eq("none")
    expect(Doorkeeper::Application.find_by(uid: body["client_id"]).confidential?).to be(false)
  end

  # A secret handed out over an unauthenticated endpoint protects nothing;
  # PKCE does the work instead. Returning one would invite a client to
  # rely on it.
  it "never issues a client secret" do
    register(redirect_uris: ["https://claude.ai/cb"])

    expect(response.parsed_body).not_to have_key("client_secret")
  end

  it "defaults to the narrowest scope when none is asked for" do
    register(redirect_uris: ["https://claude.ai/cb"])

    expect(response.parsed_body["scope"]).to eq("discovery:read")
  end

  # Better to fail here than at authorize, where a person is already
  # looking at a consent screen they cannot complete.
  it "rejects a scope this server does not grant" do
    register(redirect_uris: ["https://claude.ai/cb"], scope: "menus:teleport")

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error_description"]).to include("menus:teleport")
  end

  describe "redirect URIs" do
    it "requires at least one" do
      register(client_name: "No redirect")

      expect(response).to have_http_status(:bad_request)
    end

    # RFC 8252: a native client uses loopback or a scheme it owns.
    it "accepts loopback and a reverse-DNS private-use scheme" do
      register(redirect_uris: ["http://127.0.0.1:8976/callback", "com.example.app:/oauth"])

      expect(response).to have_http_status(:created)
    end

    # An authorization code on a cleartext hop to a public host is a code
    # anyone on the path can steal.
    it "refuses plain http to anywhere but loopback" do
      register(redirect_uris: ["http://evil.test/cb"])

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a bare scheme that any app could claim" do
      register(redirect_uris: ["myapp:/cb"])

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a relative URI" do
      register(redirect_uris: ["/cb"])

      expect(response).to have_http_status(:bad_request)
    end
  end

  # An unnamed client would render as an empty consent screen, which is
  # worse than one that is obviously unnamed.
  it "falls back to a placeholder name" do
    register(redirect_uris: ["https://claude.ai/cb"])

    expect(response.parsed_body["client_name"]).to eq("Unnamed MCP client")
  end
end
