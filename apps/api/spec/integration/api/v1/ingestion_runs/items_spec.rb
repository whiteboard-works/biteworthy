require "swagger_helper"

# Documents the existing verify endpoints (no behavior change): the
# item list, the per-item decision PATCH, and bulk accept_all. The
# creator-or-admin gate returns 403 for anyone else.
# Shared response shape for the two list-returning operations (a
# method, not a constant — a constant inside the describe block leaks
# onto Object).
def ingestion_items_response_schema
  {
    type: :object,
    required: %w[items],
    properties: {
      items: { type: :array, items: { "$ref" => "#/components/schemas/IngestionItemPayload" } }
    }
  }
end

RSpec.describe "ingestion_runs/items", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/ingestion_runs/{ingestion_run_id}/items" do
    parameter name: :ingestion_run_id, in: :path, type: :string, format: :uuid

    get("List a run's staged items (owner or admin)") do
      tags "Ingestion"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "items in position order") do
        schema ingestion_items_response_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:ingestion_run_id) do
          run = create(:ingestion_run, :staged, user: account)
          create(:ingestion_item, ingestion_run: run)
          run.id
        end
        run_test!
      end

      response(403, "not the run's creator and not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:ingestion_run_id) { create(:ingestion_run, user: create(:user)).id }
        run_test!
      end
    end
  end

  path "/api/v1/ingestion_runs/{ingestion_run_id}/items/{id}" do
    parameter name: :ingestion_run_id, in: :path, type: :string, format: :uuid
    parameter name: :id, in: :path, type: :string, format: :uuid

    patch("Decide a staged item: accept / edit / reject / undo") do
      tags "Ingestion"
      consumes "application/json"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[decision],
        description: "decision: accepted promotes (admin ⇒ confirmed joins, community ⇒ " \
                     "suggested); pending undoes a prior decision. Edit fields apply " \
                     "before an accept so the promoted Item carries the human's tweaks.",
        properties: {
          decision:    { type: :string, enum: %w[accepted edited rejected pending] },
          name:        { type: :string },
          description: { type: :string },
          ingredients_payload: { type: :array, items: { type: :object, additionalProperties: true } },
          tags_payload:        { type: :array, items: { type: :object, additionalProperties: true } },
          addons_payload:      { type: :array, items: { type: :object, additionalProperties: true } },
          unresolved_ingredients: { type: :array, items: { type: :string } },
          unresolved_tags:        { type: :array, items: { type: :string } }
        }
      }

      response(200, "the updated item") do
        schema "$ref" => "#/components/schemas/IngestionItemPayload"
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:run)  { create(:ingestion_run, :staged, user: account) }
        let(:ingestion_run_id) { run.id }
        let(:id)   { create(:ingestion_item, ingestion_run: run).id }
        let(:body) { { decision: "rejected" } }
        run_test!
      end

      response(422, "unknown decision value") do
        schema type: :object,
               properties: {
                 error:   { type: :string },
                 allowed: { type: :array, items: { type: :string } }
               }
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:run)  { create(:ingestion_run, :staged, user: account) }
        let(:ingestion_run_id) { run.id }
        let(:id)   { create(:ingestion_item, ingestion_run: run).id }
        let(:body) { { decision: "maybe" } }
        run_test!
      end
    end
  end

  path "/api/v1/ingestion_runs/{ingestion_run_id}/items/accept_all" do
    parameter name: :ingestion_run_id, in: :path, type: :string, format: :uuid

    post("Bulk-accept every still-pending item") do
      tags "Ingestion"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(200, "all items after the bulk accept") do
        schema ingestion_items_response_schema
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:ingestion_run_id) do
          run = create(:ingestion_run, :staged, user: account)
          # Empty payloads: this doc spec pins the response shape, not
          # slug resolution (the request specs cover promotion).
          create(:ingestion_item, ingestion_run: run,
                                  ingredients_payload: [], tags_payload: [], prices_payload: [])
          run.id
        end
        run_test!
      end
    end
  end
end
