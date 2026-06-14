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

    delete("Delete the caller's account (legal remediation E2)") do
      tags "Auth"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"

      response(204, "account deleted — personal data removed, menu-graph attribution nulled") do
        let(:account) { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end

        # Personal record that must be destroyed with the account.
        let!(:review) { create(:review, user: account) }
        # Shared menu-graph rows that must survive, with attribution nulled.
        let!(:created_restaurant) { create(:restaurant, created_by_user: account) }
        let!(:ingestion_run)      { create(:ingestion_run, user: account) }

        run_test! do
          expect(User.exists?(account.id)).to be(false)
          expect(UserProfile.exists?(user_id: account.id)).to be(false)
          # Personal review is gone.
          expect(Review.exists?(review.id)).to be(false)
          # Shared graph survives; the user attribution is nulled, not deleted.
          expect(created_restaurant.reload.created_by_user_id).to be_nil
          expect(ingestion_run.reload.user_id).to be_nil
        end
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end
    end
  end
end
