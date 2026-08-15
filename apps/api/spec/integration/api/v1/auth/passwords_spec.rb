require "swagger_helper"

RSpec.describe "auth/passwords", type: :request do
  path "/api/v1/auth/password" do
    post("Request a password-reset email") do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      description "Always answers 202, whether or not the email has an account — " \
                  "the response must not reveal which addresses exist. The emailed " \
                  "link lands on the web app's /reset-password page."
      parameter name: :user, in: :body, required: true, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[email],
            properties: {
              email: { type: :string, format: :email }
            }
          }
        }
      }

      response(202, "reset email queued if the account exists") do
        let!(:account) { create(:user, email: "forgetful@example.com") }
        let(:user)     { { user: { email: "forgetful@example.com" } } }
        run_test!
      end
    end

    put("Set a new password with an emailed reset token") do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      parameter name: :user, in: :body, required: true, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[reset_password_token password password_confirmation],
            properties: {
              reset_password_token: { type: :string },
              password:              { type: :string },
              password_confirmation: { type: :string }
            }
          }
        }
      }

      response(200, "password updated") do
        schema type: :object,
               required: %w[status],
               properties: { status: { type: :string, enum: %w[password_updated] } }
        let!(:account) { create(:user, email: "resetting@example.com") }
        let(:user) do
          { user: { reset_password_token: account.send_reset_password_instructions,
                    password: "new-pass-123", password_confirmation: "new-pass-123" } }
        end
        run_test!
      end

      response(422, "token invalid/expired, or the new password fails validation") do
        schema type: :object,
               required: %w[errors],
               properties: { errors: { type: :array, items: { type: :string } } }
        let(:user) do
          { user: { reset_password_token: "bogus",
                    password: "new-pass-123", password_confirmation: "new-pass-123" } }
        end
        run_test!
      end
    end
  end
end
