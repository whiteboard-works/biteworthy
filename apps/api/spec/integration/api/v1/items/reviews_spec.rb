require "swagger_helper"

RSpec.describe "items/reviews", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  review_schema = {
    type: :object,
    required: %w[id item_id rating created_at],
    properties: {
      id:         { type: :string, format: :uuid },
      item_id:    { type: :string, format: :uuid },
      rating:     { type: :integer },
      body:       { type: :string, nullable: true },
      photo_url:  { type: :string, nullable: true },
      created_at: { type: :string, format: "date-time" },
      updated_at: { type: :string, format: "date-time" },
      photo_offer: {
        type: :object,
        nullable: true,
        properties: {
          status:  { type: :string, enum: %w[pending rate_limited failed] },
          code:    { type: :string },
          message: { type: :string },
          id:      { type: :string, format: :uuid }
        }
      }
    }
  }

  path "/api/v1/items/{item_id}/reviews" do
    parameter name: :item_id, in: :path, type: :string, format: :uuid

    post("Create a review of this dish") do
      tags "Reviews"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[rating],
        properties: {
          rating: { type: :integer, description: "1 to 5." },
          body: { type: :string, nullable: true },
          offer_as_dish_photo: {
            type: :boolean,
            description: "When true, also queue the review photo as a pending dish-photo " \
                         "submission. Requires a multipart photo and owns_rights."
          },
          owns_rights: {
            type: :boolean,
            description: "Required when offer_as_dish_photo is true. Must be true, 'true', or '1'."
          }
        }
      }

      response(201, "the new review") do
        schema review_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:body) { { rating: 5, body: "Loved it." } }
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:body) { { rating: 5 } }
        run_test!
      end
    end
  end
end
