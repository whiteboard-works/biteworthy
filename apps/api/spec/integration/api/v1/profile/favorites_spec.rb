require "swagger_helper"

RSpec.describe "profile/favorites", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }

  path "/api/v1/profile/favorites" do
    get("The caller's saved restaurants + dishes, newest first") do
      tags "Profile"
      description "Authenticated. Deliberately includes draft/closed (not archived) " \
                  "restaurants so the page can grey out a dead link instead of hiding it."
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "favorited restaurants + dishes") do
        schema type: :object,
               required: %w[restaurants items],
               properties: {
                 restaurants: { type: :array, items: { "$ref" => "#/components/schemas/FavoriteRestaurantRef" } },
                 items: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id name status restaurant],
                     properties: {
                       id:         { type: :string, format: :uuid },
                       name:       { type: :string },
                       status:     { type: :string, enum: %w[draft published removed] },
                       restaurant: { "$ref" => "#/components/schemas/FavoriteRestaurantRef" }
                     }
                   }
                 }
               }

        let(:restaurant) { create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city) }
        let(:item)       { create(:item, :published, restaurant: restaurant) }
        let(:Authorization) { bearer_for(user) }

        before do
          create(:favorite_restaurant, user: user, restaurant: restaurant)
          create(:favorite_item, user: user, item: item)
        end

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["restaurants"].sole["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
          expect(body["items"].sole["restaurant"]["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
        end
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end
  end
end
