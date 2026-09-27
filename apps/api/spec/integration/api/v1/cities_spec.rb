require "swagger_helper"

RSpec.describe "cities", type: :request do
  path "/api/v1/cities" do
    get("List every city we cover") do
      tags "Cities"
      description "Public. Includes cities with no published restaurants yet, so a new " \
                  "city can take its first restaurant."
      produces "application/json"

      response(200, "all cities, name-ordered") do
        schema type: :object,
               required: %w[cities],
               properties: { cities: { type: :array, items: { "$ref" => "#/components/schemas/City" } } }

        before do
          create(:city, slug: "salt-lake-city", name: "Salt Lake City", region: "Utah")
          create(:city, slug: "durango", name: "Durango", region: "Colorado")
        end

        run_test! do |response|
          # A city with nothing published is still listed: that is the
          # whole reason this endpoint exists.
          expect(JSON.parse(response.body)["cities"].map { |c| c["slug"] }).to eq(%w[durango salt-lake-city])
        end
      end
    end
  end
end
