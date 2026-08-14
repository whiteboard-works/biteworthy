require "swagger_helper"

RSpec.describe "profile", type: :request do
  path "/api/v1/profile" do
    get("Read the caller's dietary profile") do
      tags "Profile"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"

      response(200, "the profile payload") do
        schema "$ref" => "#/components/schemas/ProfilePayload"
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

    patch("Update the caller's dietary profile") do
      tags "Profile"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt>"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        description: "All fields are optional. Arrays replace wholesale; " \
                     "dietary_profile_slug is additive (unions the preset's " \
                     "avoid lists onto whatever else you sent). The avoid " \
                     "lists also accept add_/remove_ forms for incremental " \
                     "edits — use those from any screen that changes one " \
                     "entry at a time, because a rebuilt array silently " \
                     "reverts anything another client added since it " \
                     "loaded. Sending both forms for one list is a 422.\n\n" \
                     "An id in an avoid list has to *resolve*, not merely " \
                     "be a UUID: `format: uuid` is a syntax rule, and an " \
                     "id naming no ingredient or tag would save fine and " \
                     "then match no dish, so the safety filter would " \
                     "silently do nothing. Only ids a request **adds** are " \
                     "checked — one already stored stays acceptable even if " \
                     "its taxonomy node was since removed, so a stale entry " \
                     "can never lock someone out of editing their own " \
                     "filter.",
        properties: {
          avoid_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
          avoid_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
          add_avoid_ingredient_ids:    { type: :array, items: { type: :string, format: :uuid } },
          remove_avoid_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
          add_avoid_tag_ids:           { type: :array, items: { type: :string, format: :uuid } },
          remove_avoid_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
          prefer_tag_ids:       { type: :array, items: { type: :string, format: :uuid } },
          liked_ingredient_ids:    { type: :array, items: { type: :string, format: :uuid } },
          liked_tag_ids:           { type: :array, items: { type: :string, format: :uuid } },
          disliked_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
          disliked_tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
          strictness:           { type: :string, enum: %w[relaxed balanced strict] },
          dietary_profile_slug: { type: :string },
          acknowledge_disclaimer: {
            type: :boolean,
            description: "When true, server-stamps disclaimer_acknowledged_at " \
                         "(first acknowledgment only). Sent by onboarding."
          }
        }
      }

      response(200, "updated profile payload") do
        schema "$ref" => "#/components/schemas/ProfilePayload"
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { strictness: "strict" } }
        run_test!
      end

      response(200, "acknowledging the allergen disclaimer stamps a timestamp") do
        schema "$ref" => "#/components/schemas/ProfilePayload"
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { acknowledge_disclaimer: true } }
        run_test! do |response|
          json = JSON.parse(response.body)
          # The flag is server-stamped, not echoed from the client.
          expect(json["disclaimer_acknowledged_at"]).to be_present
          expect(account.profile.reload.disclaimer_acknowledged_at).to be_present
        end
      end

      response(404, "unknown dietary_profile_slug") do
        schema "$ref" => "#/components/schemas/Error"
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { dietary_profile_slug: "no-such-preset" } }
        run_test!
      end

      # One block, not two: OpenAPI carries a single response per status,
      # so a second `response(422, …)` here would not document a second
      # cause — it would overwrite this description with whichever ran
      # last. The causes are named here instead, and the avoid-id refusal
      # is exercised as behaviour in
      # `spec/requests/api/v1/profile_spec.rb`.
      response(422, "invalid strictness, an avoid id that names no ingredient or tag, " \
                    "or a list sent in both wholesale and add_/remove_ form") do
        schema "$ref" => "#/components/schemas/ValidationErrors"
        let(:account)       { create(:user, password: "password123") }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { strictness: "yolo" } }
        run_test!
      end
    end
  end
end
