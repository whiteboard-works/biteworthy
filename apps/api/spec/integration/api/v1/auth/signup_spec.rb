require "swagger_helper"

RSpec.describe "auth/signup", type: :request do
  path "/api/v1/auth/signup" do
    post("Sign up a new user (email + password)") do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      parameter name: :user, in: :body, required: true, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[email password password_confirmation handle],
            properties: {
              email:                 { type: :string, format: :email },
              password:              { type: :string, minLength: 8 },
              password_confirmation: { type: :string, minLength: 8 },
              handle:                { type: :string, pattern: "^[a-z0-9_]{3,30}$" },
              display_name:          { type: :string, nullable: true }
            }
          }
        }
      }

      response(201, "user created — JWT in Authorization header") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let(:user) do
          { user: { email: "fresh@example.com", password: "password123",
                    password_confirmation: "password123", handle: "fresh_user",
                    display_name: "Fresh User" } }
        end
        run_test!
      end

      response(422, "validation failed (e.g. duplicate email or invalid handle)") do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:user) do
          create(:user, email: "taken@example.com")
          { user: { email: "taken@example.com", password: "password123",
                    password_confirmation: "password123", handle: "taken_user" } }
        end
        run_test!
      end
    end
  end
end
