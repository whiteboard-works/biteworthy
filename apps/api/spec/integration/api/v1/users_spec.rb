require "swagger_helper"

RSpec.describe "users", type: :request do
  path "/api/v1/users/{handle}" do
    parameter name: :handle, in: :path, type: :string,
              description: "3-30 chars, [A-Za-z0-9_]"

    get("Public user profile by handle") do
      tags "Users"
      description "Public — anonymous and authenticated callers get the same payload. " \
                  "Sensitive fields (email, dietary profile, jti, …) are intentionally absent."
      produces "application/json"
      security [ {}, { bearerAuth: [] } ]

      response(200, "public profile + recent visible reviews") do
        schema type: :object,
               required: %w[handle display_name member_since reviews_count
                            restaurants_reviewed_count recent_reviews],
               properties: {
                 handle:                     { type: :string },
                 display_name:               { type: :string, nullable: true },
                 member_since:               { type: :string, format: "date-time" },
                 reviews_count:              { type: :integer },
                 restaurants_reviewed_count: { type: :integer },
                 recent_reviews: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id item rating body photo_url created_at],
                     properties: {
                       id: { type: :string, format: :uuid },
                       item: {
                         type: :object,
                         required: %w[id name restaurant],
                         properties: {
                           id:   { type: :string, format: :uuid },
                           name: { type: :string },
                           restaurant: {
                             type: :object,
                             required: %w[id slug name web_path],
                             properties: {
                               id:       { type: :string, format: :uuid },
                               slug:     { type: :string },
                               name:     { type: :string },
                               web_path: { type: :string }
                             }
                           }
                         }
                       },
                       rating:     { type: :integer },
                       body:       { type: :string, nullable: true },
                       photo_url:  { type: :string, nullable: true },
                       created_at: { type: :string, format: "date-time" }
                     }
                   }
                 }
               }

        let(:city)       { create(:city, slug: "durango", name: "Durango", region: "Colorado") }
        let(:restaurant) { create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city) }
        let(:item)       { create(:item, :published, restaurant: restaurant) }
        let(:reviewer)   { create(:user, handle: "taco_fan_1") }
        let(:handle)     { reviewer.handle }

        before { create(:review, user: reviewer, item: item, body: "Great!") }

        run_test! do |response|
          body = JSON.parse(response.body)
          restaurant_json = body["recent_reviews"].sole["item"]["restaurant"]
          expect(restaurant_json["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
        end
      end

      response(404, "unknown handle") do
        schema "$ref" => "#/components/schemas/Error"
        let(:handle) { "nobody_here" }
        run_test!
      end
    end
  end
end
