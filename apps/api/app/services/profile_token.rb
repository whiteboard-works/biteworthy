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

  # The TS header calls strict structural validation one of the two real
  # protections here, since the token is minted client-side and signing
  # would be theater. That validation stopped at "an array of strings",
  # which let `ai: ["peanut"]` through — and because the avoid lists are
  # compared in Ruby by array intersection, a junk id matches no dish and
  # is indistinguishable from an empty filter. The person who followed a
  # shared link would be handed a menu that says it is filtered to the
  # sharer's profile and is not filtered at all. Refusing the token says
  # so; the items endpoint already turns this into a 422.
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

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

      raise InvalidTokenError, "ai must be an array of ingredient ids" unless id_array?(ai)
      raise InvalidTokenError, "at must be an array of tag ids" unless id_array?(at)
      raise InvalidTokenError, "s must be one of #{STRICTNESSES.join('|')}" unless STRICTNESSES.include?(s)
      raise InvalidTokenError, "exp must be a number" unless exp.is_a?(Numeric)
      raise InvalidTokenError, "expired" if exp <= now

      Decoded.new(avoid_ingredient_ids: ai, avoid_tag_ids: at, strictness: s)
    end

    private

    def id_array?(value)
      value.is_a?(Array) && value.all? { |id| id.is_a?(String) && id.match?(UUID) }
    end

    # `Base64.urlsafe_decode64` requires padding; the token format
    # strips it. Add it back so the decode succeeds.
    def pad_for_decode(token)
      pad = (4 - (token.length % 4)) % 4
      token + ("=" * pad)
    end
  end
end
