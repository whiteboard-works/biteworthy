# Phase 3.9 — encode/decode shareable profile tokens.
#
# `/r/:slug?p=<token>` lets anyone with the URL pre-filter a menu to
# the encoder's profile without signing in. The TypeScript side at
# packages/filter-engine/src/profile-token.ts is the canonical
# implementation; this Ruby side must produce + accept byte-identical
# tokens.
#
# Format: base64url(JSON.generate({ v:, ai:, at:, s:, exp: })). Short
# keys keep URLs reasonable; `v` lets the schema evolve later.
#
# Legal remediation E6 — v2 adds `exp` (Unix-seconds expiry). A shared
# link carries the sharer's avoid-lists + strictness (dietary data), so
# it must not live forever; decode rejects an expired token. v1 tokens
# (no expiry) are no longer accepted. See the TS module's header for why
# the token is not cryptographically signed (it's minted client-side).

class ProfileToken
  VERSION = 2
  STRICTNESSES = %w[relaxed balanced strict].freeze
  # Default lifetime of a shared link: 30 days.
  TTL_SECONDS = 30 * 24 * 60 * 60

  Decoded = Struct.new(:avoid_ingredient_ids, :avoid_tag_ids, :strictness, keyword_init: true)

  class InvalidTokenError < StandardError; end

  class << self
    # `expires_at` (Unix seconds) overrides the default TTL — used by the
    # cross-language parity spec so the encoded bytes are deterministic.
    def encode(avoid_ingredient_ids:, avoid_tag_ids:, strictness:, expires_at: nil)
      payload = {
        v:   VERSION,
        ai:  Array(avoid_ingredient_ids),
        at:  Array(avoid_tag_ids),
        s:   strictness,
        exp: expires_at || (Time.now.to_i + TTL_SECONDS)
      }
      Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    end

    def decode(token, now: Time.now.to_i)
      raise InvalidTokenError, "empty" if token.to_s.empty?

      json = begin
        Base64.urlsafe_decode64(pad_for_decode(token))
      rescue ArgumentError
        raise InvalidTokenError, "not base64url"
      end

      payload = begin
        JSON.parse(json)
      rescue JSON::ParserError
        raise InvalidTokenError, "not JSON"
      end

      raise InvalidTokenError, "not an object" unless payload.is_a?(Hash)
      raise InvalidTokenError, "unsupported version: #{payload['v']}" unless payload["v"] == VERSION

      ai  = payload["ai"]
      at  = payload["at"]
      s   = payload["s"]
      exp = payload["exp"]

      raise InvalidTokenError, "ai must be an array of strings" unless ai.is_a?(Array) && ai.all?(String)
      raise InvalidTokenError, "at must be an array of strings" unless at.is_a?(Array) && at.all?(String)
      raise InvalidTokenError, "s must be one of #{STRICTNESSES.join('|')}" unless STRICTNESSES.include?(s)
      raise InvalidTokenError, "exp must be a number" unless exp.is_a?(Numeric)
      raise InvalidTokenError, "expired" if exp <= now

      Decoded.new(avoid_ingredient_ids: ai, avoid_tag_ids: at, strictness: s)
    end

    private

    # `Base64.urlsafe_decode64` requires padding; the token format
    # strips it. Add it back so the decode succeeds.
    def pad_for_decode(token)
      pad = (4 - (token.length % 4)) % 4
      token + ("=" * pad)
    end
  end
end
