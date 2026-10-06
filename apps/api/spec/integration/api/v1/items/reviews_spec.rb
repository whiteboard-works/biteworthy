require "swagger_helper"

RSpec.describe "items/reviews", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  def jpeg_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/clean-photo.jpg"),
      "image/jpeg"
    )
  end

  review_schema = {
    type: :object,
    required: %w[id item_id rating created_at user],
    properties: {
      id:         { type: :string, format: :uuid },
      item_id:    { type: :string, format: :uuid },
      user: {
        type: :object,
        required: %w[id handle],
        properties: {
          id:           { type: :string, format: :uuid },
          handle:       { type: :string },
          display_name: { type: :string, nullable: true }
        }
      },
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

  image_error_schema = {
    type: :object,
    required: %w[error],
    properties: {
      error:   { type: :string, description: "too_large, too_many_pixels, unsupported_type, or unprocessable_image." },
      message: { type: :string }
    }
  }

  # rswag OAS3 copies the *first* body/formData param that has a schema
  # into requestBody, and only serializes `in: :formData` fields into the
  # multipart payload. Declare the object schema first so OpenAPI has
  # `photo` as binary, then the top-level form fields so run_test hits
  # ReviewsController (params[:rating], params[:photo]).
  create_body = {
    type: :object,
    required: %w[rating],
    properties: {
      rating: { type: :integer, description: "1 to 5." },
      body: { type: :string, nullable: true },
      photo: {
        type: :string,
        format: :binary,
        description: "JPEG, PNG, WebP, or HEIC. Required when offer_as_dish_photo is true. EXIF/GPS is stripped."
      },
      offer_as_dish_photo: {
        type: :boolean,
        description: "When true, also queue the review photo as a pending dish-photo submission. Requires photo and owns_rights."
      },
      owns_rights: {
        type: :boolean,
        description: "Required when offer_as_dish_photo is true. Must be true, 'true', or '1'."
      }
    }
  }

  update_body = {
    type: :object,
    properties: {
      rating: { type: :integer, description: "1 to 5." },
      body: { type: :string, nullable: true },
      photo: {
        type: :string,
        format: :binary,
        description: "Replacement photo. EXIF/GPS is stripped. Send an empty value to remove."
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
      parameter name: :review, in: :body, required: true, schema: create_body
      parameter name: :rating, in: :formData, type: :integer, required: false
      parameter name: :body, in: :formData, type: :string, required: false
      parameter name: :photo, in: :formData, type: :file, required: false
      parameter name: :offer_as_dish_photo, in: :formData, type: :boolean, required: false
      parameter name: :owns_rights, in: :formData, type: :boolean, required: false

      response(201, "the new review") do
        schema review_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:rating) { 5 }
        let(:body) { "Loved it." }
        let(:photo) { jpeg_upload }
        let(:offer_as_dish_photo) { true }
        let(:owns_rights) { true }
        run_test! do |response|
          expect(response.parsed_body["photo_url"]).to be_present
          expect(response.parsed_body["photo_offer"]).to include("status" => "pending")
        end
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:rating) { 5 }
        run_test!
      end
    end
  end

  path "/api/v1/reviews/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Update the caller's own review") do
      tags "Reviews"
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :review, in: :body, schema: update_body
      parameter name: :rating, in: :formData, type: :integer, required: false
      parameter name: :body, in: :formData, type: :string, required: false
      parameter name: :photo, in: :formData, type: :file, required: false

      response(200, "the updated review, including a replacement photo") do
        schema review_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:id) { create(:review, user: account, rating: 3).id }
        let(:rating) { 5 }
        let(:body) { "Even better on a second visit." }
        let(:photo) { jpeg_upload }
        run_test! do |response|
          expect(response.parsed_body["rating"]).to eq(5)
          expect(response.parsed_body["photo_url"]).to be_present
        end
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:id) { create(:review).id }
        let(:rating) { 4 }
        run_test!
      end

      response(422, "unreadable or disallowed replacement photo") do
        schema image_error_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:id) { create(:review, user: account).id }
        let(:photo) do
          Rack::Test::UploadedFile.new(
            StringIO.new("%PDF-not-an-image"),
            "application/pdf",
            original_filename: "menu.pdf"
          )
        end
        run_test! do |response|
          expect(response.parsed_body["error"]).to eq("unsupported_type")
        end
      end
    end
  end
end
