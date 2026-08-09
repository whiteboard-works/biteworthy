require "rails_helper"

# Legal remediation E12 — rack-attack throttling. It's disabled in the
# test env by default (so the rest of the request specs aren't throttled
# from 127.0.0.1); this spec turns it on with a fresh in-memory counter.
RSpec.describe "API rate limiting (legal E12)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    # The safelist memoizes its verdict per credential for 60s in-process,
    # so a tier flipped between examples would otherwise be invisible.
    Biteworthy::SuperAdminCredential.reset!
    # rack-attack counts into FIXED wall-clock windows, so a burst that
    # straddles a boundary splits across two counters and never trips the
    # limit — an intermittent CI failure. Freezing time keeps all the
    # requests in one window.
    freeze_time { example.run }
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.reset!
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Biteworthy::SuperAdminCredential.reset!
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

  # `/mcp` had no ceiling at all — the general rule keys on `/api/`, and
  # the MCP door does not live there. `get_menu` loads every item at a
  # restaurant and filters in Ruby, so an unbounded anonymous loop against
  # it is the cheapest way there is to spend the box's CPU.
  describe "the MCP door" do
    def rpc(headers = {})
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }.merge(headers)
    end

    it "throttles an anonymous burst" do
      31.times { rpc }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
    end

    it "lets a normal anonymous session through" do
      5.times { rpc }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    # A credential gets its own bucket and a higher ceiling. Without that,
    # every MCP client behind one company's NAT shares a counter and they
    # throttle each other — the failure the file's operational caveat
    # already describes for the auth endpoints.
    it "gives a credentialed caller headroom an anonymous one does not have" do
      user = create(:user)
      _, secret = McpToken.issue!(user: user, name: "Claude Code")

      31.times { rpc("Authorization" => "Bearer #{secret}") }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    # Two credentials must not share a counter, or one busy client
    # throttles everyone else who happens to be on the same address.
    it "counts two credentials separately" do
      first  = McpToken.issue!(user: create(:user), name: "one").last
      second = McpToken.issue!(user: create(:user), name: "two").last

      100.times { rpc("Authorization" => "Bearer #{first}") }
      rpc("Authorization" => "Bearer #{second}")

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  # The super tier is exempt from every throttle. What makes that safe is
  # that the credential is *verified* rather than read — the tempting
  # version of this safelist decodes the JWT payload and trusts `sub`,
  # which would let anyone opt out of rate limiting by claiming an id.
  # The forged-token example below is the one that would catch that.
  describe "the super-admin safelist" do
    def rpc(headers = {})
      post "/mcp",
           params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }.merge(headers)
    end

    it "exempts a super admin's MCP token from the credential ceiling" do
      _, secret = McpToken.issue!(user: create(:user, :super_admin), name: "shell")

      200.times { rpc("Authorization" => "Bearer #{secret}") }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "does not exempt a plain admin" do
      _, secret = McpToken.issue!(user: create(:user, :admin), name: "mod")

      200.times { rpc("Authorization" => "Bearer #{secret}") }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "exempts a super admin's Devise JWT on the /api surface" do
      user = create(:user, :super_admin)
      token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)

      400.times { get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" } }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    # An unsigned token carrying a real super admin's id is exactly what
    # an attacker would send. It must buy nothing.
    it "ignores a forged token that names a super admin" do
      user   = create(:user, :super_admin)
      forged = JWT.encode({ "sub" => user.id }, "not-the-signing-key", "HS256")

      400.times { get "/api/v1/me", headers: { "Authorization" => "Bearer #{forged}" } }

      expect(response).to have_http_status(:too_many_requests)
    end

    # A safelist runs ahead of every throttle, so without a bound it is
    # an amplifier: a unique bearer per request misses the cache by
    # construction and forces a fresh credential lookup that nothing is
    # rate limiting. These two pin that resolution itself is bounded, and
    # that the bound does not fall on the person it exists to exempt.
    def spray_garbage(count)
      count.times do |i|
        get "/api/v1/me", headers: { "Authorization" => "Bearer garbage-#{i}-#{SecureRandom.hex(8)}" }
      end
    end

    it "stops taking attacker-supplied strings to the database after a small budget" do
      allow(Doorkeeper::AccessToken).to receive(:by_token).and_call_original

      spray_garbage(40)

      expect(Doorkeeper::AccessToken)
        .to have_received(:by_token)
        .at_most(Biteworthy::SuperAdminCredential::RESOLUTIONS_PER_IP).times
    end

    # A verified signature is not something a stranger can supply, so the
    # query behind it is not spammable and must not be charged. This is
    # the credential nearly every real request carries — and, because the
    # web app proxies authenticated calls from one Next-server IP,
    # charging it would have let ordinary signed-in traffic drain the
    # bucket and lock the tier out at its busiest.
    it "never sends a verified JWT to the opaque-token lookups" do
      token, = Warden::JWTAuth::UserEncoder.new.call(create(:user, :super_admin), :user, nil)
      allow(Doorkeeper::AccessToken).to receive(:by_token).and_call_original

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }

      expect(Doorkeeper::AccessToken).not_to have_received(:by_token)
    end

    it "keeps exempting a super admin after garbage has drained the budget" do
      token, = Warden::JWTAuth::UserEncoder.new.call(create(:user, :super_admin), :user, nil)

      spray_garbage(40)
      400.times { get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" } }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    # A properly-signed token stays signature-valid after sign-out —
    # `JTIMatcher` revokes by rotating `users.jti`, not by invalidating
    # the signature. A safelist that checked only the signature would
    # hand a captured or post-logout token a bypass of every throttle,
    # `auth/ip` included, until it expired.
    it "ignores a signed token whose jti has been rotated by sign-out" do
      user = create(:user, :super_admin)
      token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
      user.update!(jti: SecureRandom.uuid)
      Biteworthy::SuperAdminCredential.reset!

      400.times { get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" } }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
