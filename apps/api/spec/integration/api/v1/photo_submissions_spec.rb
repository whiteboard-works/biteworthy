require "swagger_helper"

RSpec.describe "photo_submissions", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  diner_schema = {
    type: :object,
    required: %w[id item_id status owns_rights credit_name created_at],
    properties: {
      id:               { type: :string, format: :uuid },
      item_id:          { type: :string, format: :uuid },
      status:           { type: :string, enum: %w[pending approved rejected withdrawn approve_keep] },
      rejection_reason: { type: :string, nullable: true,
                          enum: %w[not_this_dish low_quality inappropriate not_food duplicate] },
      owns_rights:      { type: :boolean },
      review_id:        { type: :string, format: :uuid, nullable: true },
      photo_url:        { type: :string, nullable: true },
      credit_name:      { type: :string },
      created_at:       { type: :string, format: "date-time" },
      reviewed_at:      { type: :string, format: "date-time", nullable: true }
    }
  }

  admin_schema = diner_schema.merge(
    required: diner_schema[:required] + %w[user item],
    properties: diner_schema[:properties].merge(
      user: {
        type: :object,
        properties: {
          id:           { type: :string, format: :uuid, nullable: true },
          handle:       { type: :string, nullable: true },
          display_name: { type: :string, nullable: true }
        }
      },
      item: {
        type: :object,
        required: %w[id name restaurant],
        properties: {
          id:        { type: :string, format: :uuid },
          name:      { type: :string },
          photo_url: { type: :string, nullable: true },
          restaurant: {
            type: :object,
            properties: {
              id:   { type: :string, format: :uuid },
              name: { type: :string },
              slug: { type: :string }
            }
          }
        }
      }
    )
  )

  path "/api/v1/items/{item_id}/photo_submissions" do
    parameter name: :item_id, in: :path, type: :string, format: :uuid

    post("Submit a diner photo of this dish") do
      tags "Photo submissions"
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :photo, in: :formData, type: :file, required: true,
                description: "JPEG, PNG, WebP, or HEIC. EXIF/GPS is stripped before storage."
      parameter name: :owns_rights, in: :formData, type: :boolean, required: true,
                description: "Must be true, 'true', or '1' — the diner confirms they took the photo."

      response(201, "pending submission") do
        schema diner_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:photo) do
          Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/clean-photo.jpg"),
            "image/jpeg"
          )
        end
        let(:owns_rights) { true }
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:item_id) { create(:item, :published, restaurant: create(:restaurant, :published)).id }
        let(:photo) { nil }
        let(:owns_rights) { true }
        run_test!
      end
    end
  end

  path "/api/v1/photo_submissions" do
    get("The caller's own dish-photo submissions") do
      tags "Photo submissions"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "the caller's submissions newest-first") do
        schema type: :object,
               required: %w[photo_submissions pagination],
               properties: {
                 photo_submissions: { type: :array, items: diner_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:dish_photo_submission, user: account) }
        run_test!
      end
    end
  end

  path "/api/v1/photo_submissions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    delete("Withdraw a pending submission") do
      tags "Photo submissions"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(204, "withdrawn") do
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:id) { create(:dish_photo_submission, user: account).id }
        run_test!
      end
    end
  end

  path "/api/v1/admin/photo_submissions" do
    get("Admin dish-photo moderation queue") do
      tags "Admin"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :status, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[pending approved approve_keep rejected withdrawn all] }
      parameter name: :item_id, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "submissions newest-first + pagination") do
        schema type: :object,
               required: %w[photo_submissions pagination],
               properties: {
                 photo_submissions: { type: :array, items: admin_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:status) { "all" }
        let(:item_id) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:dish_photo_submission) }
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:status) { nil }
        let(:item_id) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/photo_submissions/{id}/approve" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Approve a diner photo, optionally setting it as the dish photo") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          replace_item_photo: {
            type: :boolean,
            description: "Copy onto Item#photo. Defaults to true when the dish has no photo."
          }
        }
      }

      response(200, "the approved submission") do
        schema admin_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:dish_photo_submission).id }
        let(:body) { { replace_item_photo: true } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/photo_submissions/{id}/reject" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Reject a diner photo with a reason") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[reason],
        properties: {
          reason: { type: :string, enum: %w[not_this_dish low_quality inappropriate not_food duplicate] }
        }
      }

      response(200, "the rejected submission") do
        schema admin_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:dish_photo_submission).id }
        let(:body) { { reason: "low_quality" } }
        run_test!
      end
    end
  end
end
