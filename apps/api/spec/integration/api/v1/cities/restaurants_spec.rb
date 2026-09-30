require "swagger_helper"

RSpec.describe "cities/restaurants", type: :request do
  path "/api/v1/cities/{city_slug}/restaurants" do
    parameter name: :city_slug, in: :path, type: :string
    parameter name: :profile, in: :query, type: :string, required: true,
              description: "DietaryProfile slug to rank by"

    get("Rank a city's published restaurants by a dietary preset") do
      tags "Cities"
      description "Public. Backs the SSR /durango/[diet] SEO pages. Ranked by " \
                  "visible_count DESC, then name ASC. 404s on an unknown city or " \
                  "unknown profile slug."
      produces "application/json"

      response(200, "city + profile metadata + ranked restaurants") do
        schema type: :object,
               required: %w[city profile restaurants],
               properties: {
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
                 profile: {
                   type: :object,
                   required: %w[id slug name description],
                   properties: {
                     id:          { type: :string, format: :uuid },
                     slug:        { type: :string },
                     name:        { type: :string },
                     description: { type: :string, nullable: true }
                   }
                 },
                 restaurants: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id slug name web_path visible_count hidden_count total_count],
                     properties: {
                       id:            { type: :string, format: :uuid },
                       slug:          { type: :string },
                       name:          { type: :string },
                       web_path:      { type: :string },
                       visible_count: { type: :integer },
                       hidden_count:  { type: :integer },
                       total_count:   { type: :integer }
                     }
                   }
                 }
               }

        let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }
        let!(:vegan_preset) { create(:dietary_profile, slug: "vegan", name: "Vegan") }
        let!(:restaurant) do
          create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city)
        end
        let(:city_slug) { city.slug }
        let(:profile)   { vegan_preset.slug }

        before { create(:item, :published, :confirmed, restaurant: restaurant, name: "Veggie", ingredients: []) }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["restaurants"].sole["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
        end
      end

      response(404, "unknown city slug") do
        schema "$ref" => "#/components/schemas/Error"
        let(:city_slug) { "nope" }
        let(:profile)   { "vegan" }
        run_test!
      end
    end
  end
end
