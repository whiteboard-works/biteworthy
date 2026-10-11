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
        schema "$ref" => "#/components/schemas/RestaurantDetail"

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
