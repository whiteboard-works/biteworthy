require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
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
end
