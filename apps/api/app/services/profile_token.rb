# Phase 3.9 — encode/decode shareable profile tokens.
#
# `/r/:slug?p=<token>` lets anyone with the URL pre-filter a menu to
# the encoder's profile without signing in. The TypeScript side at
# packages/filter-engine/src/profile-token.ts is the canonical
# implementation; this Ruby side must produce + accept byte-identical
# tokens.
#
# Format: base64url(JSON.generate({ v:, ai:, at:, s: })). Short keys
# keep URLs reasonable; `v` lets the schema evolve later.

class ProfileToken
  VERSION = 1
  STRICTNESSES = %w[relaxed balanced strict].freeze

  Decoded = Struct.new(:avoid_ingredient_ids, :avoid_tag_ids, :strictness, keyword_init: true)

  class InvalidTokenError < StandardError; end

  class << self
    def encode(avoid_ingredient_ids:, avoid_tag_ids:, strictness:)
      payload = {
        v:  VERSION,
        ai: Array(avoid_ingredient_ids),
        at: Array(avoid_tag_ids),
        s:  strictness
      }
      Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    end

    def decode(token)
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

      ai = payload["ai"]
      at = payload["at"]
      s  = payload["s"]

      raise InvalidTokenError, "ai must be an array of strings" unless ai.is_a?(Array) && ai.all?(String)
      raise InvalidTokenError, "at must be an array of strings" unless at.is_a?(Array) && at.all?(String)
      raise InvalidTokenError, "s must be one of #{STRICTNESSES.join('|')}" unless STRICTNESSES.include?(s)

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
