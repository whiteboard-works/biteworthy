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
                     source:               { type: :string, enum: %w[none preset user_profile] },
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
                       popularity:     { type: :integer },
                       ingredient_ids: { type: :array, items: { type: :string, format: :uuid } },
                       tag_ids:        { type: :array, items: { type: :string, format: :uuid } },
                       status:         { type: :string, enum: %w[visible hidden] },
                       reasons: {
                         type: :array,
                         items: {
                           type: :object,
                           required: %w[kind],
                           properties: {
                             kind:          { type: :string, enum: %w[avoid_ingredient avoid_tag unconfirmed_strict] },
                             ingredient_id: { type: :string, format: :uuid },
                             tag_id:        { type: :string, format: :uuid },
                             confidence:    { type: :string, enum: %w[confirmed suggested inferred] }
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
        run_test!
      end
    end
  end
end
