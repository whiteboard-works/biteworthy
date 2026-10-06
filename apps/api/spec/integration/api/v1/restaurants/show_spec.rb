require "swagger_helper"

RSpec.describe "restaurants/show", type: :request do
  path "/api/v1/restaurants/{id}" do
    parameter name: :id, in: :path, type: :string,
              description: "Published restaurant id or slug"

    get("Show one published restaurant") do
      tags "Restaurants"
      description "Public. `favorited` seeds the detail page's save button — always false " \
                  "for an anonymous caller."
      produces "application/json"
      security [ {}, { bearerAuth: [] } ]

      response(200, "the restaurant") do
        schema type: :object,
               required: %w[id slug name about phone website status web_path
                            claimed_at claimed_by_user_id city time_zone hours favorited],
               properties: {
                 id:                 { type: :string, format: :uuid },
                 slug:               { type: :string },
                 name:               { type: :string },
                 about:              { type: :string, nullable: true },
                 phone:              { type: :string, nullable: true },
                 website:            { type: :string, nullable: true },
                 status:             { type: :string, enum: %w[draft published closed] },
                 web_path:           { type: :string },
                 claimed_at:         { type: :string, format: "date-time", nullable: true },
                 claimed_by_user_id: { type: :string, format: :uuid, nullable: true },
                 city: {
                   type: :object,
                   required: %w[id slug name region],
                   properties: {
                     id:     { type: :string, format: :uuid },
                     slug:   { type: :string },
                     name:   { type: :string },
                     region: { type: :string, nullable: true }
                   }
                 },
                 time_zone: { type: :string, nullable: true, description: "IANA timezone (e.g. America/Denver)" },
                 hours: {
                   type: :array,
                   description: "Opening hours sorted by day_of_week then opens_at. " \
                                "Supports multiple shifts per day (lunch/dinner). " \
                                "Null times mean closed that day.",
                   items: {
                     type: :object,
                     required: %w[day_of_week opens_at closes_at],
                     properties: {
                       day_of_week: { type: :integer, description: "0=Sunday, 6=Saturday" },
                       opens_at:    { type: :string, nullable: true, pattern: "^[0-2][0-9]:[0-5][0-9]$" },
                       closes_at:   { type: :string, nullable: true, pattern: "^[0-2][0-9]:[0-5][0-9]$" }
                     }
                   }
                 },
                 favorited: { type: :boolean, description: "Always false for an anonymous caller." }
               }

        let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado", time_zone: "America/Denver") }
        let(:restaurant) do
          create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city)
        end
        let(:id) { restaurant.id }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
          expect(body["favorited"]).to eq(false)
          expect(body["time_zone"]).to eq("America/Denver")
          expect(body["hours"]).to be_an(Array)
        end
      end

      response(404, "not found (unknown id/slug, or not published)") do
        schema "$ref" => "#/components/schemas/Error"
        let(:id) { "00000000-0000-0000-0000-000000000000" }
        run_test!
      end
    end
  end
end
