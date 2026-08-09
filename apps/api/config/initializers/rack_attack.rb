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
# OPERATIONAL CAVEAT (per-IP attribution): throttling keys on `req.ip`,
# which is the real client only for traffic that reaches Rails directly
# (mobile, and the browser's own calls) or through a proxy that sets
# `X-Forwarded-For` and that Rails trusts. The web app proxies some calls
# server-side (auth, profile, dmca, review mutations, and a signed-in
# reader's menu refetch), so those arrive from the Next server's IP —
# meaning web users share one bucket and could trip a throttle together.
# Before relying on per-client throttling in production, forward the
# client IP from the Next proxy (X-Forwarded-For) and trust it in Rails;
# otherwise treat these limits as a per-edge guard, not per-user.
#
# What keeps that bucket survivable today is that the proxy is used only
# where a credential has to travel. Menu reads are the highest-volume
# path in the product, and an anonymous one goes browser-to-Rails
# directly and lands in its own bucket
# (`fetchRestaurantItemsClient` in apps/web). If that ever changes —
# if the web app starts proxying reads it does not need a cookie for —
# this ceiling becomes a shared budget for the entire web tier and the
# X-Forwarded-For work above stops being optional.
#
# Note that trusting X-Forwarded-For is not free: Rails is publicly
# reachable, so the header has to be accepted only from the known edge
# (config.action_dispatch.trusted_proxies), or anyone can forge it and
# opt out of every throttle here.
class Rack::Attack
  # In-memory counter store. Single-process is fine for the launch
  # footprint; swap to a shared store (Solid Cache / Redis) when the API
  # runs multiple processes and per-process buckets stop being accurate.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # General per-IP ceiling across the whole API surface. Generous enough
  # that a normal session never notices; low enough that a scraper does.
  throttle("api/ip", limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Tighter ceiling on the auth endpoints (login + signup) to blunt
  # credential-stuffing / account-enumeration bursts.
  throttle("auth/ip", limit: 10, period: 20.seconds) do |req|
    req.ip if req.post? && req.path.start_with?("/api/v1/auth/")
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
