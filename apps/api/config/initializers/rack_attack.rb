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
# (mobile) or through a proxy that sets `X-Forwarded-For` and that Rails
# trusts. The web app proxies some calls server-side (auth, profile,
# dmca, review mutations), so those arrive from the Next server's IP —
# meaning web users would share one bucket and could trip the tight auth
# throttle together. Before relying on per-client auth throttling in
# production, forward the client IP from the Next proxy (X-Forwarded-For)
# and trust it in Rails; otherwise treat the auth limit as a per-edge
# guard, not per-user.
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
