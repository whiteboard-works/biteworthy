require "swagger_helper"

RSpec.describe "restaurant_claims", type: :request do
  path "/api/v1/restaurants/{restaurant_id}/claim" do
    parameter name: :restaurant_id, in: :path, type: :string,
              description: "Restaurant UUID or slug"

    post("Ask to claim a restaurant; emails a verification link") do
      tags "Restaurants"
      description "Authenticated. Emails `<web_path>/claim?t=<token>` to the given address."
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[email], properties: { email: { type: :string } }
      }

      let(:claim_city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }
      let(:claimable) { create(:restaurant, :published, slug: "smelter", city: claim_city, website: "https://smelter.example") }
      let(:restaurant_id) { claimable.id }

      response(202, "verification sent") do
        schema type: :object,
               required: %w[status email auto_acceptable expires_at],
               properties: {
                 status:          { type: :string },
                 email:           { type: :string },
                 auto_acceptable: { type: :boolean },
                 expires_at:      { type: :string }
               }
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(create(:user), :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { email: "owner@smelter.example" } }

        # The emailed link is the owner's only way in; it must land on the
        # location-based page, not the old flat URL.
        run_test! do
          url = ActiveJob::Base.queue_adapter.enqueued_jobs
                               .find { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }["arguments"]
                               .dig(3, "args", 1)
          expect(url).to include("/restaurants/usa/colorado/durango/smelter/claim?t=")
        end
      end

      response(422, "missing email") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) do
          token, _ = Warden::JWTAuth::UserEncoder.new.call(create(:user), :user, nil)
          "Bearer #{token}"
        end
        let(:body) { { email: "" } }
        run_test!
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        let(:body) { { email: "owner@smelter.example" } }
        run_test!
      end
    end
  end

  path "/api/v1/restaurants/{restaurant_id}/claim/verify" do
    parameter name: :restaurant_id, in: :path, type: :string,
              description: "Restaurant id or slug"
    parameter name: :t, in: :query, type: :string, description: "Verification token"

    get("Verify a claim token and mark the restaurant claimed") do
      tags "Restaurants"
      description "Anonymous — the token alone is the credential."
      produces "application/json"

      response(200, "restaurant marked claimed") do
        schema type: :object,
               required: %w[status restaurant],
               properties: {
                 status: { type: :string, enum: %w[claimed] },
                 restaurant: {
                   type: :object,
                   required: %w[id slug name web_path claimed_at claimed_by_user_id],
                   properties: {
                     id:                 { type: :string, format: :uuid },
                     slug:               { type: :string },
                     name:               { type: :string },
                     web_path:           { type: :string },
                     claimed_at:         { type: :string, format: "date-time" },
                     claimed_by_user_id: { type: :string, format: :uuid }
                   }
                 }
               }

        let(:city)       { create(:city, slug: "durango", name: "Durango", region: "Colorado") }
        let(:requester)  { create(:user) }
        let(:restaurant) do
          create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city,
                 website: "https://ninis.example.com")
        end
        let(:restaurant_id) { restaurant.id }
        let(:t) do
          result = RestaurantClaim.request_claim(restaurant: restaurant, requester: requester,
                                                  email: "owner@ninis.example.com")
          result.suggestion.payload["token"]
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["restaurant"]["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
          expect(body["restaurant"]["claimed_by_user_id"]).to eq(requester.id)
        end
      end

      response(422, "invalid, expired, or already-claimed-by-someone-else token") do
        schema type: :object,
               required: %w[error kind],
               properties: {
                 error: { type: :string },
                 kind:  { type: :string, enum: %w[InvalidTokenError ExpiredTokenError AlreadyClaimedError] }
               }

        let(:restaurant_id) { create(:restaurant, :published).id }
        let(:t) { "bogus-token" }

        run_test! do |response|
          expect(JSON.parse(response.body)["kind"]).to eq("InvalidTokenError")
        end
      end
    end
  end
end
