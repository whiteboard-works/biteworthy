require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
  # Insulate the spec from whatever credentials live in the local
  # .env / CI secrets — same reason as spec/requests/admin_spec.rb.
  around do |example|
    original_user = ENV["ADMIN_USERNAME"]
    original_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_USERNAME"] = "admin"
    ENV["ADMIN_PASSWORD"] = "admin"
    example.run
  ensure
    ENV["ADMIN_USERNAME"] = original_user
    ENV["ADMIN_PASSWORD"] = original_password
  end

  let(:restaurant) { create(:restaurant, :published) }
  let(:basic_auth) do
    creds = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin")
    { "Authorization" => creds }
  end

  it "challenges for HTTP Basic auth without credentials" do
    get "/admin/dashboard"

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to match(/\ABasic realm=/)
  end

  it "rejects wrong credentials with 401" do
    bad = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong-pass")
    get "/admin/dashboard", headers: { "Authorization" => bad }

    expect(response).to have_http_status(:unauthorized)
  end

  it "renders the dashboard with metrics for an authorized caller" do
    create(:ingestion_run, restaurant: restaurant,
           api_cost_cents: 25, latency_ms: 3_200,
           cached_input_tokens: 5_000, uncached_input_tokens: 5_000)

    get "/admin/dashboard", headers: basic_auth

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cost &amp; latency dashboard")
    expect(response.body).to include("Today")
    expect(response.body).to include("Last 7 days")
    expect(response.body).to include("Last 30 days")
    expect(response.body).to include("Cache hit rate")
  end

  describe "community counters (Phase 6.4)" do
    it "counts community runs separately from admin runs and shows spend vs ceiling" do
      scanner = create(:user, password: "password123", is_admin: false)
      admin_u = create(:user, password: "password123", is_admin: true)
      create(:ingestion_run, restaurant: restaurant, user: scanner, api_cost_cents: 30)
      create(:ingestion_run, restaurant: restaurant, user: admin_u, api_cost_cents: 70)

      get "/admin/dashboard", headers: basic_auth

      expect(response.body).to include("Community ingestion (today, UTC)")
      community_card = response.body[/data-period="community-today".*?<\/div>\s*<\/div>/m]
      expect(community_card).to include(">1<")          # 1 community run (admin's excluded)
      expect(response.body).to include("$1.00 /")        # 30 + 70 cents total spend
      expect(response.body).to include("$20.00")         # default ceiling
    end
  end
end
