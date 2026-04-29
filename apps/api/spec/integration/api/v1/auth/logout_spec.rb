require "swagger_helper"

RSpec.describe "auth/logout", type: :request do
  path "/api/v1/auth/logout" do
    delete("Log out — rotates the user's `jti` so the JWT is dead immediately") do
      tags "Auth"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> from signup or login"

      response(204, "logged out") do
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        run_test!
      end
    end
  end
end
