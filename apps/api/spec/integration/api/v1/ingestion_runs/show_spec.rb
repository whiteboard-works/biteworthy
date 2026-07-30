require "swagger_helper"

# Documents the existing endpoint (no behavior change) — the verify
# UIs and the web admin both poll it; api-types were hand-written
# until this spec existed.
RSpec.describe "ingestion_runs/show", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/ingestion_runs/{id}" do
    parameter name: :id, in: :path, type: :string, format: :uuid

    get("Read a run's status + counters (owner or admin)") do
      tags "Ingestion"
      produces "application/json"
      security [bearerAuth: []]
      parameter name: :Authorization, in: :header, type: :string, required: true,
                description: "Bearer <jwt> — the run's creator or an admin"

      response(200, "the run") do
        schema "$ref" => "#/components/schemas/IngestionRunPayload"
        let(:account) { create(:user) }
        let(:Authorization) { bearer_for(account) }
        let(:id) { create(:ingestion_run, user: account).id }
        run_test!
      end

      response(404, "someone else's run (deliberately not 403), or unknown id") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        let(:id) { create(:ingestion_run, user: create(:user)).id }
        run_test!
      end
    end
  end
end
