# frozen_string_literal: true

# Answers one question for `Rack::Attack`: does the credential on this
# request belong to a super admin?
#
# It exists because the throttles run as middleware, before Devise, so
# there is no `current_user` to ask. The naive version — base64-decode
# the JWT payload and read `sub` — is what `apps/web`'s `getServerUserId`
# does, and it is explicitly documented there as UI-only for good reason:
# an unverified `sub` is attacker-supplied, so it would let anyone opt out
# of every rate limit by claiming an id. Every path below **verifies**.
#
# Three credential shapes reach the API, and all three are checked so the
# tier means the same thing at whichever door the operator is standing:
#
#   * a Devise JWT (web + mobile) — signature-verified by devise-jwt's own
#     decoder, which is the same code the real authentication path runs
#   * an `bw_mcp_` token — SHA-256 digest lookup, active scope only
#   * a Doorkeeper OAuth access token — `by_token`, accessible? only
#
# The decision is cached against a digest of the credential, never the
# credential itself, so a cache dump is not a set of working secrets.
# 60 seconds is short enough that a revoked super admin stops being
# exempt promptly and long enough that this is not a database lookup per
# request.
#
# **Deliberately its own in-process store, not `Rails.cache`.** This runs
# in middleware on every request that carries a bearer token, and
# `Rails.cache` is Solid Cache — Postgres — so routing it there would add
# a query to the hottest authenticated path in the app in order to avoid
# a query. A `MemoryStore` makes the common answer (`false`, for everyone
# who is not a super admin) free after the first hit, at the cost of
# being per-process. That is the same trade `Rack::Attack.cache.store`
# already makes two files over, for the same reason.
#
# **Every failure path returns false.** An exempt-on-error safelist is a
# rate limiter that turns itself off under exactly the conditions that
# make rate limiting matter.
module Biteworthy
  class SuperAdminCredential
    CACHE_TTL = 60.seconds

    # A safelist runs *before* every throttle, which is the whole point
    # and also the hazard: without a bound, an unauthenticated caller can
    # send a different garbage bearer on every request and force a fresh
    # credential lookup each time — cache-missing by construction, and
    # unthrottled by definition. The rate limiter would become the
    # amplifier.
    #
    # So resolution is rate limited per IP — but **only the part of it
    # that a stranger can make us do.**
    #
    # The split matters. Verifying a Devise JWT is pure CPU: a signature
    # an attacker cannot forge gates the single `User.find_by` behind it,
    # so that path is not spammable and is never charged. What *is*
    # spammable is a lookup keyed on an attacker-supplied opaque string —
    # the `bw_mcp_` digest query and Doorkeeper's `by_token` — because any
    # random text reaches them. Only those are budgeted.
    #
    # Charging every cache miss instead would put the cost on the wrong
    # people: `rack_attack.rb`'s operational caveat notes the web app
    # proxies authenticated calls, so every signed-in user arrives from
    # one Next-server IP. Past ten distinct users a minute the bucket for
    # that IP would be empty, and the next super admin whose 60s cache
    # entry lapsed would be refused a refresh and lose the exemption — at
    # exactly the busy moment the tier exists for.
    RESOLUTIONS_PER_IP = 10
    RESOLUTION_WINDOW  = 1.minute

    class << self
      def store
        @store ||= ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)
      end

      # Its own store, not the verdict cache's. `MemoryStore` prunes by
      # insertion order once it passes its size, and it does not know a
      # counter from a verdict — sharing one would let a spray of verdicts
      # evict counters mid-window (resetting an attacker's budget) and let
      # counters evict a super admin's `true` (forcing a re-resolution).
      def budget_store
        @budget_store ||= ActiveSupport::Cache::MemoryStore.new(size: 512.kilobytes)
      end

      # Tests that flip a user's tier mid-example need the memo gone.
      def reset!
        store.clear
        budget_store.clear
      end

      def exempt?(request)
        secret = bearer(request)
        return false if secret.blank?

        cached = store.read(cache_key(secret))
        return cached unless cached.nil?

        resolved = user_for(secret, ip: request.ip)
        # "We declined to look" is not "not a super admin", so it is not
        # cached — caching it would lock a legitimate caller out for the
        # rest of the TTL over one unlucky moment.
        return false if resolved == :over_budget

        verdict = !!resolved&.is_super_admin?
        store.write(cache_key(secret), verdict, expires_in: CACHE_TTL)
        verdict
      rescue StandardError => e
        # Never let a broken lookup decide the request. Reported rather
        # than swallowed: a safelist that silently stopped working would
        # look exactly like one that was never reached.
        Rails.logger.warn("[rack-attack] super-admin safelist failed: #{e.class}")
        Rails.error.report(e, handled: true, context: { component: "super_admin_safelist" })
        false
      end

      private

      def bearer(request)
        request.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/i, 1]
      end

      # A digest, not the token: a throttle-adjacent cache is not a place
      # to keep a credential (the same reasoning as `mcp_bearer_key`).
      def cache_key(secret)
        "super_admin_credential:#{Digest::SHA256.hexdigest(secret)}"
      end

      # Counts only the lookups a stranger can force: cache hits are free,
      # and so is the JWT path, whose query sits behind a signature.
      # Bucketed by wall-clock window rather than a sliding count — the
      # same shape `Rack::Attack` itself uses, and it needs no eviction
      # pass.
      def resolution_budget?(ip)
        return true if ip.blank?

        key   = "resolutions:#{ip}:#{(Time.current.to_i / RESOLUTION_WINDOW).to_i}"
        # MemoryStore#increment initialises a missing key to the amount,
        # so the first call in a window returns 1 — no seeding needed.
        spent = budget_store.increment(key, 1, expires_in: RESOLUTION_WINDOW * 2)
        # nil means the store could not count (not the case for
        # MemoryStore, but a swap to a shared store should not silently
        # start refusing every super admin). The cache-hit path above
        # already covers the steady state, so allowing here is safe.
        spent.nil? || spent <= RESOLUTIONS_PER_IP
      end

      # Returns a `User`, `nil`, or `:over_budget`.
      #
      # Ordered by who can make us do the work, not just by cost. The JWT
      # path runs first and unbudgeted because its DB query sits behind a
      # signature check no stranger can pass — and because it is the
      # credential nearly every real request carries, so budgeting it
      # would starve exactly the callers the tier is for. Everything below
      # it takes an opaque attacker-suppliable string straight to a query,
      # so it is charged.
      def user_for(secret, ip:)
        user = jwt_user(secret)
        return user if user

        return :over_budget unless resolution_budget?(ip)

        return mcp_token_user(secret) if secret.start_with?(McpToken::PREFIX)

        oauth_user(secret)
      end

      def mcp_token_user(secret) = McpToken.authenticate(secret)&.user

      def oauth_user(secret)
        token = Doorkeeper::AccessToken.by_token(secret)
        return nil unless token&.accessible?

        User.find_by(id: token.resource_owner_id)
      end

      # devise-jwt's own decoder — verifies the signature and the expiry
      # against `Warden::JWT::Config`, and raises on anything it does not
      # like, which the caller turns into `false`.
      #
      # The `jti` comparison is the revocation half, and it is not
      # optional: `User` includes `JTIMatcher`, so signing out rotates
      # `users.jti` and leaves the old token signature-valid but dead for
      # authentication. Checking only the signature would let a captured
      # or post-logout token keep a total throttle exemption — including
      # from `auth/ip`, the credential-stuffing guard — for the rest of
      # its lifetime. The other two credential shapes check liveness
      # (`McpToken.active`, `accessible?`); this one has to as well.
      def jwt_user(secret)
        payload = Warden::JWTAuth::TokenDecoder.new.call(secret)
        user    = User.find_by(id: payload["sub"])
        return nil unless user && payload["jti"].present? && user.jti == payload["jti"]

        user
      rescue JWT::DecodeError
        nil
      end
    end
  end
end
