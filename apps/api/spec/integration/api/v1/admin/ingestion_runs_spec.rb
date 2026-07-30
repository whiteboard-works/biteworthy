require "swagger_helper"

RSpec.describe "admin/ingestion_runs", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/admin/ingestion_runs" do
    get("Cross-user ingestion runs queue") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"
      parameter name: :status, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[queued extracting resolving staged published failed] },
                description: "Filter by run status (unknown values are ignored)"
      parameter name: :community, in: :query, type: :string, required: false,
                schema: { type: :string, enum: %w[true] },
                description: "Only runs scanned by non-admin users"
      parameter name: :restaurant_id, in: :query, type: :string, required: false,
                description: "Filter to one restaurant"
      parameter name: :limit, in: :query, type: :integer, required: false,
                description: "Page size (default 25, max 100)"
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "runs newest-first + pagination") do
        schema type: :object,
               required: %w[runs pagination],
               properties: {
                 runs: {
                   type: :array,
                   items: {
                     type: :object,
                     required: %w[id status decision_counts],
                     properties: {
                       id:                { type: :string, format: :uuid },
                       status:            { type: :string, enum: %w[queued extracting resolving staged published failed] },
                       enrichment_status: { type: :string, nullable: true },
                       input_kind:        { type: :string },
                       failure_message:   { type: :string, nullable: true },
                       api_cost_cents:    { type: :integer, nullable: true },
                       created_at:        { type: :string, format: "date-time" },
                       user: {
                         type: :object, nullable: true,
                         properties: {
                           id:       { type: :string, format: :uuid },
                           handle:   { type: :string },
                           email:    { type: :string },
                           is_admin: { type: :boolean }
                         }
                       },
                       restaurant: {
                         type: :object, nullable: true,
                         properties: {
                           id:     { type: :string, format: :uuid },
                           name:   { type: :string },
                           slug:   { type: :string },
                           status: { type: :string, enum: %w[draft published closed] }
                         }
                       },
                       decision_counts: {
                         type: :object,
                         required: %w[pending accepted rejected edited],
                         properties: {
                           pending:  { type: :integer },
                           accepted: { type: :integer },
                           rejected: { type: :integer },
                           edited:   { type: :integer }
                         }
                       }
                     }
                   }
                 },
                 pagination: { "$ref" => "#/components/schemas/Pagination" }
               }

        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:status)        { nil }
        let(:community)     { nil }
        let(:restaurant_id) { nil }
        let(:limit)         { nil }
        let(:offset)        { nil }
        before { create(:ingestion_item) } # one run with one pending item
        run_test!
      end

      response(404, "authenticated but not an admin") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:status)        { nil }
        let(:community)     { nil }
        let(:restaurant_id) { nil }
        let(:limit)         { nil }
        let(:offset)        { nil }
        run_test!
      end
    end
  end

  path "/api/v1/admin/ingestion_runs/{id}/re_extract" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    post("Rewind a run to :queued and re-fire extraction") do
      tags "Admin"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> for a user with is_admin"

      response(200, "run rewound and ExtractMenuJob enqueued") do
        schema type: :object,
               required: %w[id status],
               properties: {
                 id:     { type: :string, format: :uuid },
                 status: { type: :string, enum: %w[queued] }
               }
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:ingestion_run, :failed).id }
        run_test!
      end

      response(422, "run is already published — its items are live") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user, :admin)) }
        let(:id) { create(:ingestion_run, status: "published").id }
        run_test!
      end
    end
  end
end
