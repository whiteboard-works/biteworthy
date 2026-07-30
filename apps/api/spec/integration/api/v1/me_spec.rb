require "swagger_helper"

RSpec.describe "me", type: :request do
  path "/api/v1/me" do
    get("Read the caller's own identity payload") do
      tags "Auth"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"

      response(200, "the caller's user payload (incl. is_admin)") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let(:account) { create(:user, password: "password123") }
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
