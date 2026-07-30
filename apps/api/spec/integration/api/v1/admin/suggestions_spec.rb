require "swagger_helper"

RSpec.describe "admin/suggestions", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  suggestion_schema = {
    type: :object,
    required: %w[id kind status payload created_at],
    properties: {
      id:          { type: :string, format: :uuid },
      kind:        { type: :string },
      status:      { type: :string, enum: %w[pending accepted rejected] },
      payload:     { type: :object, additionalProperties: true },
      created_at:  { type: :string, format: "date-time" },
      resolved_at: { type: :string, format: "date-time", nullable: true },
      item: {
        type: :object, nullable: true,
        properties: {
          id:            { type: :string, format: :uuid },
          name:          { type: :string },
          restaurant_id: { type: :string, format: :uuid }
        }
      },
      submitter: {
        type: :object, nullable: true,
        properties: {
          id:           { type: :string, format: :uuid },
          handle:       { type: :string },
          display_name: { type: :string, nullable: true }
        }
      }
    }
  }

  path "/api/v1/admin/suggestions" do
    get("Cross-restaurant suggestion queue") do
      tags "Admin"
      description "The owner queue only covers claimed restaurants; this one covers " \
                  "everything. Accept/reject reuses PATCH /api/v1/suggestions/{id}."
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :status, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[pending accepted rejected] },
                description: "Default pending"
      parameter name: :restaurant_id, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "suggestions oldest-first (queue order) + pagination") do
        schema type: :object,
               required: %w[suggestions pagination],
               properties: {
                 suggestions: { type: :array, items: suggestion_schema },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:status) { nil }
        let(:restaurant_id) { nil }
        let(:limit)  { nil }
        let(:offset) { nil }
        before { create(:item_suggestion_pending) }
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:status) { nil }
        let(:restaurant_id) { nil }
        let(:limit)  { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/suggestions/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Accept or reject a suggestion (owner or admin)") do
      tags "Suggestions"
      description "Documents the existing Phase 4.10 endpoint (no behavior change). " \
                  "Accept materializes the change via SuggestionResolver."
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[decision],
        properties: {
          decision: { type: :string, enum: %w[accepted rejected] }
        }
      }

      response(200, "the resolved suggestion") do
        schema suggestion_schema
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id)   { create(:item_suggestion_pending).id }
        let(:body) { { decision: "rejected" } }
        run_test!
      end

      response(403, "not the claimed owner and not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:id)   { create(:item_suggestion_pending).id }
        let(:body) { { decision: "rejected" } }
        run_test!
      end
    end
  end
end
