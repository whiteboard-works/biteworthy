require "swagger_helper"

RSpec.describe "auth/refresh", type: :request do
  path "/api/v1/auth/refresh" do
    post("Refresh — mints a new JWT and rotates `jti` so the previous one dies") do
      tags "Auth"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> currently in use"

      response(200, "fresh JWT in Authorization header") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end
    end
  end
end
