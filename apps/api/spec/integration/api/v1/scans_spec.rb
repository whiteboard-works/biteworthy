require "swagger_helper"

RSpec.describe "scans", type: :request do
  let(:account)    { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:Authorization) do
    token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/scans" do
    post("Start a menu scan from a URL, pasted text, or uploaded attachments") do
      tags "Scans"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[restaurant],
        properties: {
          restaurant:     { type: :string, description: "Restaurant UUID or slug." },
          source_url:     { type: :string },
          source_text:    { type: :string },
          attachment_ids: { type: :array, items: { type: :string }, description: "Ids from POST /api/v1/attachments." }
        }
      }

      response(201, "scan queued; poll GET /api/v1/scans/{id}") do
        schema "$ref" => "#/components/schemas/ScanStarted"
        before { allow(ExtractMenuJob).to receive(:perform_later) }
        let(:body) { { restaurant: restaurant.slug, source_text: "Carne asada taco — beef, onion, cilantro. $4.50" } }
        run_test!
      end

      response(422, "no source, more than one, or one the extractor cannot take") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:body) { { restaurant: restaurant.slug } }
        run_test!
      end

      response(403, "a draft restaurant the caller did not create") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:body) { { restaurant: create(:restaurant, status: "draft").slug, source_text: "Taco" } }
        run_test!
      end

      response(404, "no such restaurant") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:body) { { restaurant: "nowhere", source_text: "Taco" } }
        run_test!
      end

      response(429, "daily scan quota or the global spend ceiling reached") do
        schema "$ref" => "#/components/schemas/ScanError"
        before do
          allow(Ingestion::StartRun).to receive(:call).and_return(Ingestion::StartRun::Result.new(error: :quota_exceeded))
        end
        let(:body) { { restaurant: restaurant.slug, source_text: "Taco" } }
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:body) { { restaurant: "anything", source_text: "x" } }
        run_test!
      end
    end
  end

  path "/api/v1/scans/{id}" do
    get("Where a scan has got to; includes the dishes once ready") do
      tags "Scans"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :id, in: :path, type: :string, required: true

      response(200, "scan status") do
        schema "$ref" => "#/components/schemas/ScanStatus"
        let(:id) do
          run = create(:ingestion_run, :staged, user: account, restaurant: restaurant)
          create(:ingestion_item, ingestion_run: run)
          run.id
        end
        run_test!
      end

      response(404, "no such scan, or someone else's") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:id) { create(:ingestion_run, :staged, user: create(:user), restaurant: restaurant).id }
        run_test!
      end
    end
  end

  path "/api/v1/scans/{id}/accept" do
    post("Publish staged dishes to the live menu") do
      tags "Scans"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :id, in: :path, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          all:      { type: :boolean, description: "Accept every still-pending dish." },
          item_ids: { type: :array, items: { type: :string } }
        }
      }

      response(200, "what was published") do
        schema "$ref" => "#/components/schemas/ScanAccepted"
        let(:id) do
          run = create(:ingestion_run, :staged, user: account, restaurant: restaurant)
          create(:ingestion_item, ingestion_run: run)
          run.id
        end
        let(:body) { { all: true } }
        run_test!
      end

      response(422, "nothing to accept, or both all and item_ids") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:id) { create(:ingestion_run, :staged, user: account, restaurant: restaurant).id }
        let(:body) { { item_ids: [] } }
        run_test!
      end

      response(404, "no such scan, or someone else's") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:id) { create(:ingestion_run, :staged, user: create(:user), restaurant: restaurant).id }
        let(:body) { { all: true } }
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:id) { "anything" }
        let(:body) { { all: true } }
        run_test!
      end
    end
  end

  path "/api/v1/scans/{id}/reject" do
    post("Mark staged dishes as not on the menu") do
      tags "Scans"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :id, in: :path, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[item_ids],
        properties: { item_ids: { type: :array, items: { type: :string } } }
      }

      response(200, "what was rejected") do
        schema "$ref" => "#/components/schemas/ScanRejected"
        let(:run)  { create(:ingestion_run, :staged, user: account, restaurant: restaurant) }
        let(:id)   { run.id }
        let(:body) { { item_ids: [ create(:ingestion_item, ingestion_run: run).id ] } }
        run_test!
      end

      response(422, "no item ids") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:id)   { create(:ingestion_run, :staged, user: account, restaurant: restaurant).id }
        let(:body) { { item_ids: [] } }
        run_test!
      end

      response(404, "no such scan, or someone else's") do
        schema "$ref" => "#/components/schemas/ScanError"
        let(:id)   { create(:ingestion_run, :staged, user: create(:user), restaurant: restaurant).id }
        let(:body) { { item_ids: [ "x" ] } }
        run_test!
      end
    end
  end
end
