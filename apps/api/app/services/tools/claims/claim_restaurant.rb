# frozen_string_literal: true

module Tools
  module Claims
    class ClaimRestaurant < Tools::Base
      audience :user

      tool_name "claim_restaurant"
      title "Claim a restaurant you own"
      description <<~TEXT
        Start the ownership claim for a restaurant. We mail a verification
        link to the address given; clicking it (or calling `verify_claim` with
        the token) is what actually grants ownership. This tool only sends the
        mail.

        Ownership unlocks the correction queue for that restaurant — an owner
        can accept edits to their own menu. Only call this when the user says
        they run the place.

        An address on the restaurant's own web domain verifies faster; anything
        else still works but waits on an admin. Already-claimed restaurants are
        rejected. Re-requesting refreshes the token, so it is safe to retry.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant slug or UUID." },
          email: {
            type: "string",
            description: "Where to send the verification link. Ask the user; never guess it."
          }
        },
        required: %w[restaurant email]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, restaurant:, email:)
        user    = context.user!
        record  = Restaurant.published.find_by_id_or_slug!(restaurant)
        address = email.to_s.strip.downcase
        raise Errors::InvalidArgument, "That does not look like an email address." unless address.include?("@")

        result = RestaurantClaim.request_claim(restaurant: record, requester: user, email: address)
        RestaurantClaimMailer.verify_email(
          result.suggestion.id, verify_url(context, record, result.suggestion)
        ).deliver_later

        ok(
          status:          "verification_sent",
          restaurant:      { id: record.id, slug: record.slug, name: record.name },
          email:           address,
          auto_acceptable: result.auto_acceptable,
          expires_at:      result.suggestion.payload["expires_at"]
        )
      rescue RestaurantClaim::AlreadyClaimedError => e
        raise Errors::InvalidArgument, e.message
      end

      def self.verify_url(context, restaurant, suggestion)
        host = context.public_host.to_s.chomp("/")
        "#{host}/restaurants/#{restaurant.slug}/claim?t=#{suggestion.payload['token']}"
      end
      private_class_method :verify_url
    end
  end
end
