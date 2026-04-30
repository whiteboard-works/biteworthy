require "rails_helper"

# Phase 1.5 mounts Avo at /admin behind HTTP Basic auth. The smoke
# spec doesn't exercise individual resource pages — it just verifies
# that the auth gate is in place and that the admin index renders for
# a properly-credentialed caller. Resource-by-resource checks land in
# Phase 4 once we have policy-based per-action authorization.

RSpec.describe "/admin (Avo) auth gate", type: :request do
  # Insulate the spec from whatever credentials live in the local
  # .env / CI secrets — the spec asserts the *gate*, not specific
  # values. Restore on teardown so other specs aren't surprised.
  around do |example|
    original_user = ENV["ADMIN_USERNAME"]
    original_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "admin"
    example.run
  ensure
    ENV["ADMIN_USERNAME"] = original_user
    ENV["ADMIN_PASSWORD"] = original_password
  end

  let(:basic_auth) do
    creds = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin")
    { "Authorization" => creds }
  end

  it "challenges for HTTP Basic auth without credentials" do
    get "/admin"

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to match(/\ABasic realm=/)
  end

  it "rejects wrong credentials with 401" do
    bad = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong-pass")

    get "/admin", headers: { "Authorization" => bad }

    expect(response).to have_http_status(:unauthorized)
  end

  it "renders the dashboard for the right credentials" do
    get "/admin", headers: basic_auth

    # Avo redirects /admin → /admin/resources/<first_resource> by
    # default, so 302 is the green path. Either 200 or 302 here is
    # proof we got past the auth gate.
    expect([200, 302]).to include(response.status)
  end
end
