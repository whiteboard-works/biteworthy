require "swagger_helper"

RSpec.describe "auth/login", type: :request do
  path "/api/v1/auth/login" do
    post("Log in with email + password") do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      parameter name: :user, in: :body, required: true, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[email password],
            properties: {
              email:    { type: :string, format: :email },
              password: { type: :string }
            }
          }
        }
      }

      response(200, "JWT issued in Authorization header") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let!(:account) { create(:user, email: "logger@example.com", password: "password123") }
        let(:user)     { { user: { email: "logger@example.com", password: "password123" } } }
        run_test!
      end

      response(401, "wrong password or unknown email") do
        let(:user) { { user: { email: "ghost@example.com", password: "wrong" } } }
        run_test!
      end
    end
  end
end
