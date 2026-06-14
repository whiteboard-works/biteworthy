require "rails_helper"

# Legal remediation E12 — rack-attack throttling. It's disabled in the
# test env by default (so the rest of the request specs aren't throttled
# from 127.0.0.1); this spec turns it on with a fresh in-memory counter.
RSpec.describe "API rate limiting (legal E12)", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.reset!
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  it "throttles a burst of auth requests from one IP with 429 + Retry-After" do
    # auth/ip rule: 10 per 20s. The 11th from the same IP is throttled
    # before it reaches the controller (the bad creds never matter).
    11.times do
      post "/api/v1/auth/login",
           params: { user: { email: "x@example.com", password: "wrong-password" } },
           as: :json
    end

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
    expect(response.parsed_body["error"]).to match(/too many requests/i)
  end

  it "lets traffic under the limit through" do
    post "/api/v1/auth/login",
         params: { user: { email: "x@example.com", password: "wrong-password" } },
         as: :json
    expect(response).not_to have_http_status(:too_many_requests)
  end
end
