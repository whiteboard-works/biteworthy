require "swagger_helper"

RSpec.describe "restaurants/items", type: :request do
  path "/api/v1/restaurants/{restaurant_id}/items" do
    parameter name: :restaurant_id, in: :path, type: :string, format: :uuid,
              description: "Published restaurant id"
    parameter name: :profile, in: :query, type: :string, required: false,
              description: "DietaryProfile slug whose avoid lists to apply"
    parameter name: :strictness, in: :query, type: :string, required: false,
              schema: { type: :string, enum: %w[relaxed balanced strict] },
              description: "Override the strictness from profile/user"
    parameter name: :profile_token, in: :query, type: :string, required: false,
              description: "A share token minted by `encodeProfileToken`, carrying " \
                           "the sharer's avoid lists and strictness. Takes precedence " \
                           "over `profile` and over the signed-in user's own profile. " \
                           "Refused with 422 when it is malformed, expired, or refers " \
                           "to an ingredient or tag that no longer exists — the last " \
                           "because the response would otherwise be labelled " \
                           "`source: \"profile_token\"` over a menu nothing was " \
                           "filtered out of."

    get("List published items at this restaurant with per-item filter status") do
      tags "Restaurants"
      produces "application/json"
      security [{}, { bearerAuth: [] }]

      response(200, "items + per-item status (visible | hidden) + reasons[]") do
        schema type: :object,
               required: %w[restaurant_id filter items],
               properties: {
                 restaurant_id: { type: :string, format: :uuid },
                 filter: {
                   type: :object,
                   properties: {
                     source:               { type: :string, enum: %w[none preset user_profile profile_token] },
                     preset_slug:          { type: :string, nullable: true },
                     strictness:           { type: :string, enum: %w[relaxed balanced strict] },
                     avoid_ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
                     avoid_tag_ids:        { type: :array, items: { type: :string, format: :uuid } }
                   }
                 },
                 items: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id restaurant_id name confidence ingredient_ids tag_ids status reasons],
                     properties: {
                       id:             { type: :string, format: :uuid },
                       restaurant_id:  { type: :string, format: :uuid },
                       name:           { type: :string },
                       description:    { type: :string, nullable: true },
                       confidence:     { type: :string, enum: %w[confirmed suggested inferred] },
                       ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
                       tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
                       status:         { type: :string, enum: %w[visible hidden] },
                       reasons: {
                         type: :array,
                         items: {
                           type: :object,
                           required: %w[kind],
                           properties: {
                             kind:              { type: :string, enum: %w[avoid_ingredient avoid_tag unconfirmed_strict] },
                             ingredient_id:     { type: :string, format: :uuid },
                             ingredient_name:   { type: :string, nullable: true },
                             ingredient_family: { type: :string, nullable: true },
                             tag_id:            { type: :string, format: :uuid },
                             tag_name:          { type: :string, nullable: true },
                             tag_family:        { type: :string, nullable: true },
                             confidence:        { type: :string, enum: %w[confirmed suggested inferred] }
                           }
                         }
                       },
                       # Phase 8.2 — taste ranks, never hides. Null /
                       # empty unless the signed-in caller's profile
                       # carries taste signals.
                       taste_score: { type: :number, nullable: true },
                       taste_reasons: {
                         type: :array,
                         items: {
                           type: :object,
                           required: %w[kind],
                           properties: {
                             kind:            { type: :string, enum: %w[liked_tag liked_ingredient] },
                             tag_id:          { type: :string, format: :uuid },
                             tag_name:        { type: :string, nullable: true },
                             ingredient_id:   { type: :string, format: :uuid },
                             ingredient_name: { type: :string, nullable: true }
                           }
                         }
                       }
                     }
                   }
                 }
               }

        let(:restaurant_id) { create(:restaurant, :published).id }
        let(:profile)       { nil }
        let(:strictness)    { nil }
        run_test!
      end

      response(404, "restaurant not found, not published, or unknown profile slug") do
        let(:restaurant_id) { "00000000-0000-0000-0000-000000000000" }
        let(:profile)       { nil }
        let(:strictness)    { nil }
        let(:profile_token) { nil }
        run_test!
      end

      # A share link is a claim that the menu below it is filtered. When
      # the token cannot support that claim the endpoint refuses rather
      # than serving an unfiltered menu under a filtered label.
      response(422, "profile_token malformed, expired, or naming ids that no longer exist") do
        schema "$ref" => "#/components/schemas/Error"
        let(:restaurant)    { create(:restaurant, :published) }
        let(:restaurant_id) { restaurant.id }
        let(:profile)       { nil }
        let(:strictness)    { nil }
        let(:profile_token) do
          ProfileToken.encode(avoid_ingredient_ids: [ SecureRandom.uuid ],
                              avoid_tag_ids: [], strictness: "balanced")
        end
        run_test!
      end
    end
  end
end
