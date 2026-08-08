# frozen_string_literal: true

module Tools
  module Claims
    class VerifyClaim < Tools::Base
      audience :user

      tool_name "verify_claim"
      title "Finish a restaurant claim"
      description <<~TEXT
        Complete an ownership claim using the token from the verification
        email. Ownership lands on the account that requested the claim, not on
        whoever calls this — the token is the credential.

        Ask the user to paste the token or the link from their inbox. Tokens
        expire after seven days; an expired one needs a fresh
        `claim_restaurant`. Calling this twice is harmless.
      TEXT

      input_schema(
        properties: {
          token: {
            type: "string",
            description: "The token from the email. Accepts the whole verification URL too."
          }
        },
        required: ["token"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, token:)
        context.user!
        suggestion = RestaurantClaim.verify(token: extract_token(token))
        restaurant = suggestion.subject

        ok(
          status: "claimed",
          restaurant: {
            id: restaurant.id, slug: restaurant.slug, name: restaurant.name,
            claimed_at: restaurant.claimed_at
          }
        )
      rescue RestaurantClaim::InvalidTokenError, RestaurantClaim::ExpiredTokenError,
             RestaurantClaim::AlreadyClaimedError => e
        raise Errors::InvalidArgument, e.message
      end

      # Users paste the whole link far more often than the bare token.
      def self.extract_token(value)
        raw = value.to_s.strip
        return raw unless raw.include?("?")

        URI.decode_www_form(URI.parse(raw).query.to_s).to_h["t"].to_s
      rescue URI::InvalidURIError
        raw
      end
      private_class_method :extract_token
    end
  end
end
