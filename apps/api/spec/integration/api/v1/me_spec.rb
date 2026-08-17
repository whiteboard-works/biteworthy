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

    patch("Update the caller's own account (handle)") do
      tags "Auth"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          # Any case in, stored lowercase (the response carries the
          # canonical spelling). The old handle frees up immediately
          # and /u/<old> stops resolving.
          handle: { type: :string, pattern: "^[A-Za-z0-9_]{3,30}$" }
        }
      }

      response(200, "the updated user payload") do
        schema "$ref" => "#/components/schemas/AuthResponse"
        let(:account) { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { handle: "Chosen_Name" } }
        run_test! do
          expect(account.reload.handle).to eq("chosen_name")
        end
      end

      response(422, "handle taken (case-insensitively) or bad format") do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:account) { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) do
          create(:user, handle: "already_taken")
          { handle: "Already_Taken" }
        end
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:body) { { handle: "whoever" } }
        run_test!
      end
    end
  end
end
