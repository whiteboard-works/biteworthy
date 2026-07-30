require "rails_helper"

# The cross-user runs queue is the web admin's moderation inbox: it
# must show every user's runs (that's the point — Avo was the only
# cross-user view before), filter to what needs attention, and count
# decisions without an N+1. Re-extract rewinds state and re-enqueues
# the job, but must never touch a published run — its items are live.
RSpec.describe "Admin ingestion runs", type: :request do
  let(:admin)     { create(:user, :admin) }
  let(:scanner)   { create(:user) }

  describe "GET /api/v1/admin/ingestion_runs" do
    it "404s non-admins and 401s the unauthenticated" do
      get "/api/v1/admin/ingestion_runs", headers: auth_headers_for(scanner)
      expect(response).to have_http_status(:not_found)

      get "/api/v1/admin/ingestion_runs"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists every user's runs newest-first with user + restaurant refs and decision counts" do
      run = create(:ingestion_run, :staged, user: scanner)
      create(:ingestion_item, ingestion_run: run)
      create(:ingestion_item, :rejected, ingestion_run: run)
      older = create(:ingestion_run, user: admin, created_at: 2.days.ago)

      get "/api/v1/admin/ingestion_runs", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["runs"].map { |r| r["id"] }).to eq([run.id, older.id])
      expect(body["pagination"]).to include("total" => 2)

      newest = body["runs"].first
      expect(newest["user"]).to include("handle" => scanner.handle, "is_admin" => false)
      expect(newest["restaurant"]).to include("id" => run.restaurant_id)
      expect(newest["decision_counts"]).to eq(
        "pending" => 1, "accepted" => 0, "rejected" => 1, "edited" => 0
      )
    end

    it "filters by status, community (non-admin scanners), and restaurant" do
      community_staged = create(:ingestion_run, :staged, user: scanner)
      create(:ingestion_run, :staged, user: admin)     # admin-scanned
      create(:ingestion_run, user: scanner)            # queued

      get "/api/v1/admin/ingestion_runs",
          params: { status: "staged", community: "true" },
          headers: auth_headers_for(admin)

      ids = response.parsed_body["runs"].map { |r| r["id"] }
      expect(ids).to eq([community_staged.id])

      get "/api/v1/admin/ingestion_runs",
          params: { restaurant_id: community_staged.restaurant_id },
          headers: auth_headers_for(admin)
      expect(response.parsed_body["runs"].map { |r| r["id"] }).to eq([community_staged.id])
    end

    it "paginates with limit/offset and reports the unfiltered-page total" do
      3.times { create(:ingestion_run, user: scanner) }

      get "/api/v1/admin/ingestion_runs", params: { limit: 2, offset: 2 },
                                          headers: auth_headers_for(admin)

      body = response.parsed_body
      expect(body["runs"].size).to eq(1)
      expect(body["pagination"]).to eq("total" => 3, "limit" => 2, "offset" => 2)
    end
  end

  describe "POST /api/v1/admin/ingestion_runs/:id/re_extract" do
    it "rewinds a failed run to :queued, clears failure state, and re-enqueues extraction" do
      run = create(:ingestion_run, :failed, user: scanner, latency_ms: 1234)

      expect do
        post "/api/v1/admin/ingestion_runs/#{run.id}/re_extract",
             headers: auth_headers_for(admin)
      end.to have_enqueued_job(ExtractMenuJob).with(run.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("id" => run.id, "status" => "queued")
      expect(run.reload).to have_attributes(
        status: "queued", failure_message: nil, latency_ms: nil, staging: {}
      )
    end

    it "clears un-promoted staged rows so the fresh extraction doesn't double the deck" do
      run = create(:ingestion_run, :staged, user: scanner)
      create(:ingestion_item, ingestion_run: run)
      create(:ingestion_item, :rejected, ingestion_run: run)

      post "/api/v1/admin/ingestion_runs/#{run.id}/re_extract",
           headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(run.reload.status).to eq("queued")
      expect(run.ingestion_items.count).to eq(0)
    end

    it "refuses a staged run that already promoted an Item — re-extracting would orphan it" do
      run  = create(:ingestion_run, :staged, user: scanner)
      item = create(:item, restaurant: run.restaurant)
      create(:ingestion_item, ingestion_run: run, decision: "accepted", item: item)
      pending_row = create(:ingestion_item, ingestion_run: run)

      post "/api/v1/admin/ingestion_runs/#{run.id}/re_extract",
           headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "has_promoted_items")
      expect(run.reload.status).to eq("staged")
      # Nothing was deleted — the refusal left the run untouched.
      expect(run.ingestion_items.ids).to contain_exactly(
        run.ingestion_items.find_by(decision: "accepted").id, pending_row.id
      )
    end

    it "refuses a published run — its items are already live" do
      run = create(:ingestion_run, user: scanner, status: "published")

      expect do
        post "/api/v1/admin/ingestion_runs/#{run.id}/re_extract",
             headers: auth_headers_for(admin)
      end.not_to have_enqueued_job(ExtractMenuJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "already_published")
      expect(run.reload.status).to eq("published")
    end

    it "404s non-admins without revealing the run exists" do
      run = create(:ingestion_run, :failed, user: scanner)
      post "/api/v1/admin/ingestion_runs/#{run.id}/re_extract",
           headers: auth_headers_for(scanner)
      expect(response).to have_http_status(:not_found)
      expect(run.reload.status).to eq("failed")
    end
  end
end
