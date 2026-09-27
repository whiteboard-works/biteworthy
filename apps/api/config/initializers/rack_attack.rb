# Legal remediation E12 — API request throttling (rack-attack).
#
# Backs the ToS "don't scrape the API at a rate that affects other
# users" rule with actual enforcement, and gives brute-force protection
# on the auth endpoints. rack-attack inserts its middleware via its
# Railtie; this file only defines the rules.
#
# Disabled in the test env by default so the request specs (which fire
# many requests from 127.0.0.1) don't trip a throttle — the dedicated
# throttle spec flips `Rack::Attack.enabled` on with its own cache.
#
# ATTRIBUTION. Signed-in /api traffic is throttled per user (verified
# Devise JWT), everything else per client IP. The web app calls Rails from
# its server for credentialed and server-rendered requests, so `req.ip` is
# the Next server there; it forwards the visitor's IP in `X-BW-Client-IP`
# with a shared secret in `X-BW-Proxy-Secret`, and `client_ip` trusts the
# forwarded address only when the secret matches `WEB_PROXY_SECRET`. Rails
# is publicly reachable, so a forwarding header nobody authenticates would
# let any caller choose their own bucket. Until the secret is set on both
# sides, anonymous web-server traffic still shares the Next server's
# bucket — signed-in traffic is per user either way. Server-rendered pages
# that are ISR-cached (home, /restaurants, /durango/*) hit Rails at most
# once per revalidate window, so they don't forward a client IP.
#
# Production needs WEB_PROXY_SECRET in three places at once: Vercel's env,
# `.kamal/secrets`, and `env.secret` in config/deploy.yml (then
# bin/kamal-secrets-push). Listing it in deploy.yml before the value exists
# fails the deploy, so that line lands with the provisioning, not before.
class Rack::Attack
  # In-memory counter store. Single-process is fine for the launch
  # footprint; swap to a shared store (Solid Cache / Redis) when the API
  # runs multiple processes and per-process buckets stop being accurate.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # The super-admin tier is exempt from every throttle below. The check
  # verifies the credential's signature (or looks up its digest) rather
  # than reading an unverified `sub` — see Biteworthy::SuperAdminCredential
  # for why that distinction is the whole safety of this block, and why it
  # returns false on every error.
  #
  # Worth knowing: this also lifts the shared `api/ip` bucket for whatever
  # IP the operator's requests arrive from, which for web traffic is the
  # Next server (see the operational caveat above). That is acceptable
  # while the roster is a couple of shell-granted accounts, and stops
  # being acceptable the moment the tier is handed to anyone else.
  safelist("super_admin") do |req|
    Biteworthy::SuperAdminCredential.exempt?(req)
  end

  # General ceiling across the whole API surface. Generous enough that a
  # normal session never notices; low enough that a scraper does.
  #
  # Keyed per signed-in user when the request carries a valid Devise JWT,
  # and per client IP otherwise. Web requests reach Rails from the Next
  # server, so an IP key alone made every web user share one bucket — a
  # few scan screens polling could 429 the whole web tier. The JWT is
  # signature-checked (pure CPU, no query): an unverified `sub` would let
  # anyone mint a fresh bucket per request.
  throttle("api/user", limit: 300, period: 5.minutes) do |req|
    api_user_key(req) if req.path.start_with?("/api/")
  end

  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    client_ip(req) if req.path.start_with?("/api/") && api_user_key(req).nil?
  end

  # Tighter ceiling on the auth endpoints (login + signup + password
  # reset) to blunt credential-stuffing / account-enumeration bursts.
  # PUT/PATCH included: the token-consuming reset endpoint is a PUT, and
  # a POST-only predicate would leave token guessing on the loose
  # api/ip ceiling.
  throttle("auth/ip", limit: 10, period: 20.seconds) do |req|
    if %w[POST PUT PATCH].include?(req.request_method) && req.path.start_with?("/api/v1/auth/")
      client_ip(req)
    end
  end

  # Reset-email requests, keyed on the target address: per-IP limits
  # can't stop one victim's inbox being bombed from many IPs (or from
  # the web proxy's single egress IP, which all browser traffic shares).
  throttle("password_reset/email", limit: 5, period: 1.hour) do |req|
    next unless req.post? && req.path == "/api/v1/auth/password"

    begin
      body  = req.body.read
      email = JSON.parse(body).dig("user", "email").to_s.strip.downcase
      email.presence
    rescue JSON::ParserError
      nil
    ensure
      req.body.rewind
    end
  end

  # Dynamic client registration (RFC 7591) is unauthenticated by design,
  # which makes it the one endpoint where an anonymous caller can create
  # rows. A real client registers once, so a handful per hour is generous.
  throttle("oauth_register/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/oauth/register"
  end

  # `/mcp` had no ceiling at all: the general rule above matches on
  # `/api/`, and the MCP door does not live there. That left the most
  # expensive read path in the product — `get_menu` loads every item at a
  # restaurant and filters in Ruby — reachable anonymously and unbounded,
  # which is a cheap way to spend the box's CPU from a laptop.
  #
  # Keyed on the credential rather than the IP wherever there is one.
  # Every MCP client behind one company's NAT would otherwise share a
  # bucket and throttle each other, which is the failure the operational
  # caveat above already describes for the auth endpoints. The bearer is
  # hashed because a throttle key is not a place to keep a secret.
  #
  # Two ceilings, because the two callers are not equally accountable: a
  # credential belongs to somebody who can be asked to stop, and a
  # credentialed session is also the one that legitimately runs six tool
  # calls in a turn. Anonymous browsing is real (public discovery works
  # without an account, deliberately) but does not need that headroom.
  throttle("mcp/credential", limit: 120, period: 1.minute) do |req|
    mcp_bearer_key(req)
  end

  throttle("mcp/anonymous_ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path == "/mcp" && mcp_bearer_key(req).nil?
  end

  # The browser half of OAuth. Not a brute-force surface — PKCE and
  # hashed secrets handle that — but every hit runs a doorkeeper lookup
  # and `/oauth/token` writes a row, so an unbounded loop here is the
  # same CPU-and-rows problem registration is already guarded against.
  throttle("oauth_flow/ip", limit: 30, period: 1.minute) do |req|
    req.ip if %w[/oauth/authorize /oauth/token].include?(req.path)
  end

  # The real client for a request the Next server forwarded on someone's
  # behalf: it sends the visitor's IP plus a shared secret, and only a
  # matching secret makes Rails believe the IP — Rails is publicly
  # reachable, so an unauthenticated forwarding header would let anyone
  # pick their own bucket. Without the secret (or before it is set) this
  # is `req.ip`, exactly the old behavior.
  def self.client_ip(req)
    secret    = ENV["WEB_PROXY_SECRET"].presence
    forwarded = req.get_header("HTTP_X_BW_CLIENT_IP").to_s.strip
    return req.ip if secret.nil? || forwarded.empty?
    return req.ip unless ActiveSupport::SecurityUtils.secure_compare(
      req.get_header("HTTP_X_BW_PROXY_SECRET").to_s, secret
    )

    IPAddr.new(forwarded).to_s
  rescue IPAddr::InvalidAddressError
    req.ip
  end

  # A user's current jti. One primary-key lookup — the same one Devise runs
  # to authenticate this request moments later — and uncached, so a token
  # revoked by sign-out stops counting as its user immediately.
  def self.current_jti(user_id)
    User.where(id: user_id).pick(:jti)
  end

  # "user:<id>" for a request carrying a valid, unexpired, unrevoked Devise
  # JWT; nil otherwise, which sends it to the IP bucket. Memoized on the env
  # because both /api throttles ask. A revoked token must not get a bucket
  # of its own — logging out repeatedly would mint fresh ones.
  def self.api_user_key(req)
    return req.env["bw.throttle_user"] if req.env.key?("bw.throttle_user")

    req.env["bw.throttle_user"] =
      begin
        bearer = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/i, 1]
        if bearer.present?
          payload = Warden::JWTAuth::TokenDecoder.new.call(bearer)
          jti     = payload["jti"].presence
          "user:#{payload['sub']}" if jti && jti == current_jti(payload["sub"])
        end
      rescue JWT::DecodeError
        nil
      end
  end

  # Nil for an anonymous caller, so the two MCP throttles above partition
  # the traffic instead of double-counting it.
  def self.mcp_bearer_key(req)
    return nil unless req.path == "/mcp"

    bearer = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/i, 1]
    return nil if bearer.blank?

    "mcp:#{Digest::SHA256.hexdigest(bearer)}"
  end

  # JSON 429 with a Retry-After so clients can back off politely.
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = (match_data[:period] || 60).to_i
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "Too many requests. Please slow down and try again shortly." }.to_json]
    ]
  end
end

# Off in test unless a spec explicitly enables it (see the throttle spec).
Rack::Attack.enabled = false if Rails.env.test?
