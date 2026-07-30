require "swagger_helper"

RSpec.describe "admin/reviews", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  review_schema = {
    type: :object,
    required: %w[id rating created_at user item],
    properties: {
      id:            { type: :string, format: :uuid },
      rating:        { type: :integer },
      body:          { type: :string, nullable: true },
      photo_url:     { type: :string, nullable: true },
      created_at:    { type: :string, format: "date-time" },
      flagged_at:    { type: :string, format: "date-time", nullable: true },
      hidden_at:     { type: :string, format: "date-time", nullable: true },
      hidden_reason: { type: :string, nullable: true, enum: %w[spam abuse duplicate off_topic] },
      user: {
        type: :object,
        properties: {
          id:           { type: :string, format: :uuid },
          handle:       { type: :string },
          display_name: { type: :string, nullable: true }
        }
      },
      item: {
        type: :object,
        properties: {
          id:   { type: :string, format: :uuid },
          name: { type: :string },
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
    }
  }

  path "/api/v1/admin/reviews" do
    get("Review moderation queue") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :visibility, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[flagged hidden visible all] },
                description: "Default flagged (reader-reported, not yet moderated)"
      parameter name: :item_id, in: :query, type: :string, required: false
      parameter name: :user_id, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "reviews newest-first + pagination") do
        schema type: :object,
               required: %w[reviews pagination],
               properties: {
                 reviews: { type: :array, items: review_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:visibility) { "all" }
        let(:item_id) { nil }
        let(:user_id) { nil }
        let(:limit)   { nil }
        let(:offset)  { nil }
        before { create(:review) }
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:visibility) { nil }
        let(:item_id) { nil }
        let(:user_id) { nil }
        let(:limit)   { nil }
        let(:offset)  { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/reviews/{id}/hide" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Hide a review with a moderation reason") do
      tags "Admin"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[reason],
        properties: {
          reason: { type: :string, enum: %w[spam abuse duplicate off_topic] }
        }
      }

      response(200, "the hidden review") do
        schema review_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:review).id }
        let(:body) { { reason: "spam" } }
        run_test!
      end

      response(422, "unknown reason") do
        schema type: :object,
               properties: {
                 error:   { type: :string },
                 allowed: { type: :array, items: { type: :string } }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:review).id }
        let(:body) { { reason: "meh" } }
        run_test!
      end
    end
  end

  path "/api/v1/admin/reviews/{id}/unhide" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Restore a hidden review") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "the restored review") do
        schema review_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) do
          review = create(:review)
          review.hide!(reason: "spam")
          review.id
        end
        run_test!
      end
    end
  end
end
