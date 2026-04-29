require "swagger_helper"

# OmniAuth start + callback paths. The "start" endpoint is documented
# but not run_test!'d here because exercising the redirect would require
# either a live provider or a real session cookie — out of scope for a
# schema-generating spec. Behavioral coverage lives in the existing
# spec/requests/api/v1/auth/omniauth_*_spec.rb.

RSpec.describe "auth/omniauth", type: :request do
  path "/api/v1/auth/{provider}" do
    parameter name: :provider, in: :path, type: :string,
              schema: { type: :string, enum: %w[google_oauth2 apple] },
              description: "OAuth provider to start the dance with"

    get("Begin the OAuth handshake — redirects to the provider's consent screen") do
      tags "Auth"
      produces "application/json"

      response(302, "redirect to provider") do
        let(:provider) { "google_oauth2" }
        # Skip the run_test! — the redirect target depends on live ENV
        # values for GOOGLE_OAUTH_CLIENT_ID. Schema only.
      end
    end
  end

  path "/api/v1/auth/{provider}/callback" do
    parameter name: :provider, in: :path, type: :string,
              schema: { type: :string, enum: %w[google_oauth2 apple] },
              description: "OAuth provider whose callback hit us"

    get("OAuth callback — finalizes the handshake and mints a JWT") do
      tags "Auth"
      produces "application/json"

      response(200, "JWT issued in Authorization header") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let(:provider) { "google_oauth2" }
        # Schema only — exercising the callback requires a mocked
        # OmniAuth env that this rswag block doesn't set up.
      end

      response(401, "OmniAuth failure (invalid_credentials, etc.)") do
        schema "$ref" => "#/components/schemas/Error"
        let(:provider) { "google_oauth2" }
      end
    end
  end
end
