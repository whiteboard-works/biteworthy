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
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :rating, in: :formData, type: :integer, required: true
      parameter name: :body, in: :formData, type: :string, required: false
      parameter name: :photo, in: :formData, type: :file, required: false,
                description: "Optional JPEG/PNG/WebP/HEIC. EXIF/GPS is stripped before storage."
      parameter name: :offer_as_dish_photo, in: :formData, type: :boolean, required: false,
                description: "When true, also queue the photo as a pending dish-photo submission."
      parameter name: :owns_rights, in: :formData, type: :boolean, required: false,
                description: "Required when offer_as_dish_photo is true. Must be true, 'true', or '1'."

      response(201, "the new review") do
        schema review_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:rating) { 5 }
        let(:body) { "Loved it." }
        let(:photo) { nil }
        let(:offer_as_dish_photo) { nil }
        let(:owns_rights) { nil }
        run_test!
      end

      response(201, "review plus a pending dish-photo offer") do
        schema review_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:rating) { 4 }
        let(:body) { "See pic." }
        let(:photo) do
          Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/test-image.jpg"),
            "image/jpeg"
          )
        end
        let(:offer_as_dish_photo) { true }
        let(:owns_rights) { true }
        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["photo_offer"]).to include("status" => "pending")
          expect(DishPhotoSubmission.find(body["photo_offer"]["id"])).to be_pending
        end
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:rating) { 5 }
        let(:body) { nil }
        let(:photo) { nil }
        let(:offer_as_dish_photo) { nil }
        let(:owns_rights) { nil }
        run_test!
      end
    end
  end
end
