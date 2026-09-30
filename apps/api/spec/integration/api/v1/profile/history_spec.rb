require "swagger_helper"

RSpec.describe "profile/history", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }

  path "/api/v1/profile/history" do
    get("The caller's recent restaurant visits, newest first") do
      tags "Profile"
      description "Authenticated. Item counts are captured AT VIEW TIME, not recomputed."
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "recent visits") do
        schema type: :object,
               required: %w[visits total],
               properties: {
                 visits: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id viewed_on updated_at items_visible_count items_hidden_count restaurant],
                     properties: {
                       id:                  { type: :string, format: :uuid },
                       viewed_on:           { type: :string, format: :date },
                       updated_at:          { type: :string, format: "date-time" },
                       items_visible_count: { type: :integer },
                       items_hidden_count:  { type: :integer },
                       restaurant: {
                         type: :object,
                         required: %w[id slug name web_path city],
                         properties: {
                           id:       { type: :string, format: :uuid },
                           slug:     { type: :string },
                           name:     { type: :string },
                           web_path: { type: :string },
                           city: {
                             type: :object,
                             required: %w[slug name region],
                             properties: {
                               slug:   { type: :string },
                               name:   { type: :string },
                               region: { type: :string, nullable: true }
                             }
                           }
                         }
                       }
                     }
                   }
                 },
                 total: { type: :integer }
               }

        let(:restaurant) { create(:restaurant, :published, slug: "ninis", name: "Ninis Taqueria", city: city) }
        let(:Authorization) { bearer_for(user) }
        let(:limit)  { nil }
        let(:offset) { nil }

        before { create(:restaurant_visit, user: user, restaurant: restaurant) }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["visits"].sole["restaurant"]["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
        end
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        let(:limit)  { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end
end
