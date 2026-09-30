require "swagger_helper"

RSpec.describe "profile/reviews", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }

  path "/api/v1/profile/reviews" do
    get("The caller's own reviews, newest first, hidden ones included") do
      tags "Profile"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "the caller's reviews") do
        schema type: :object,
               required: %w[reviews total],
               properties: {
                 total:   { type: :integer },
                 reviews: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id item rating body photo_url hidden hidden_reason created_at updated_at],
                     properties: {
                       id:   { type: :string, format: :uuid },
                       item: {
                         type: :object,
                         required: %w[id name status restaurant],
                         properties: {
                           id:         { type: :string, format: :uuid },
                           name:       { type: :string },
                           status:     { type: :string, enum: %w[draft published removed] },
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
                       rating:        { type: :integer },
                       body:          { type: :string, nullable: true },
                       photo_url:     { type: :string, nullable: true },
                       hidden:        { type: :boolean },
                       hidden_reason: { type: :string, nullable: true },
                       created_at:    { type: :string, format: "date-time" },
                       updated_at:    { type: :string, format: "date-time" }
                     }
                   }
                 }
               }
        let(:Authorization) { bearer_for(user) }
        before do
          restaurant = create(:restaurant, :published, slug: "ninis", city: city)
          create(:review, user: user, item: create(:item, restaurant: restaurant))
        end

        # The account page builds each dish link from this; without it the
        # link rendered as "undefined/items/<id>".
        run_test! do |response|
          restaurant = JSON.parse(response.body)["reviews"].sole["item"]["restaurant"]
          expect(restaurant["web_path"]).to eq("/restaurants/usa/colorado/durango/ninis")
        end
      end

      response(401, "not signed in") do
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end
  end
end
