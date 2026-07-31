require "rails_helper"

# The /api/v1/admin/* gate is the single authorization line between
# every admin capability (moderation, taxonomy edits, user promotion)
# and the public internet. This matrix pins its three contractual
# behaviors: 401 for the unauthenticated, an unrevealing 404 for
# authenticated non-admins (the namespace must not advertise itself),
# and 200 for admins. It also pins that /api/v1/me — the web /admin
# guard's probe — reports is_admin truthfully for both roles.
RSpec.describe "Api::V1::Admin gate", type: :request do
  describe "GET /api/v1/admin/dashboard" do
    it "returns 401 when unauthenticated" do
      get "/api/v1/admin/dashboard"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 (not 403) for an authenticated non-admin" do
      get "/api/v1/admin/dashboard", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("error" => "not_found")
    end

    it "returns 200 with the dashboard payload for an admin" do
      get "/api/v1/admin/dashboard", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["periods"].keys).to contain_exactly("today", "last_7_days", "last_30_days")
      expect(body["community"]).to include("ceiling_cents")
      expect(body["queues"]).to include(
        "flagged_reviews", "pending_suggestions",
        "community_published_restaurants", "staged_runs"
      )
    end

    # This exclusion previously lived in the deleted ERB dashboard spec;
    # it's the number that tells an admin how much of today's spend is
    # community scanning vs their own — counting admins would hide a
    # runaway community day.
    it "counts community runs separately from admin runs, but sums everyone's spend" do
      admin   = create(:user, :admin)
      scanner = create(:user)
      create(:ingestion_run, user: scanner, api_cost_cents: 30)
      create(:ingestion_run, user: admin, api_cost_cents: 50)

      get "/api/v1/admin/dashboard", headers: auth_headers_for(admin)

      body = response.parsed_body
      expect(body["community"]).to include(
        "runs_today" => 1, "spend_today_cents" => 80
      )
    end
  end

  describe "GET /api/v1/me" do
    it "reports is_admin: false for a regular user" do
      get "/api/v1/me", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include("is_admin" => false)
    end

    it "reports is_admin: true for an admin" do
      user = create(:user, :admin)
      get "/api/v1/me", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user"]).to include(
        "id" => user.id, "email" => user.email, "is_admin" => true
      )
    end

    it "returns 401 when unauthenticated" do
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
