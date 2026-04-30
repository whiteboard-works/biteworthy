# Phase 4.9 — restaurant claim flow.
#
# Reuses the existing `suggestions` polymorphic queue with
# `kind: "claim"` rather than introducing a new schema. The
# Suggestion holds the verification token + email + expiry in its
# `payload` jsonb. Verifying the token marks the restaurant claimed
# and accepts the Suggestion in one transaction.
#
# Domain match heuristic (per phase-4.md): the email's domain must
# match the restaurant's `website` host (with optional `www.` strip).
# A mismatch records the Suggestion for manual admin review rather
# than auto-accepting — Avo's existing Suggestion resource surfaces
# pending claims so a human can validate the off-domain ones.
class RestaurantClaim
  TOKEN_TTL = 7.days
  KIND = "claim".freeze

  Result = Struct.new(:suggestion, :auto_acceptable, keyword_init: true) do
    def auto_acceptable?
      auto_acceptable
    end
  end

  class InvalidTokenError < StandardError; end
  class ExpiredTokenError < StandardError; end
  class AlreadyClaimedError < StandardError; end

  class << self
    # Create + return a Suggestion for the requester. The token is
    # generated server-side and stored in `payload[:token]`. Caller
    # is expected to mail the link out (RestaurantClaimMailer).
    def request_claim(restaurant:, requester:, email:)
      raise AlreadyClaimedError, "restaurant already claimed" if restaurant.claimed_by_user_id.present?

      token = SecureRandom.urlsafe_base64(32)
      auto_acceptable = email_matches_website?(email, restaurant.website)

      suggestion = Suggestion.create!(
        user:    requester,
        subject: restaurant,
        kind:    KIND,
        status:  "pending",
        payload: {
          email:      email,
          token:      token,
          expires_at: TOKEN_TTL.from_now.iso8601,
          auto_acceptable: auto_acceptable
        }
      )

      Result.new(suggestion: suggestion, auto_acceptable: auto_acceptable)
    end

    # Verify a token + flip the restaurant to claimed. Idempotent —
    # if the token's already accepted, returns the same Suggestion
    # without changing state.
    def verify(token:)
      raise InvalidTokenError, "blank token" if token.to_s.empty?

      suggestion = find_by_token(token)
      raise InvalidTokenError, "token not found" unless suggestion
      restaurant = suggestion.subject
      raise InvalidTokenError, "subject is not a Restaurant" unless restaurant.is_a?(Restaurant)

      if suggestion.status == "accepted"
        # Already verified — nothing to do.
        return suggestion
      end

      expires_at = Time.iso8601(suggestion.payload["expires_at"]) rescue nil
      raise ExpiredTokenError, "token expired" if expires_at.nil? || expires_at < Time.current

      ApplicationRecord.transaction do
        if restaurant.claimed_by_user_id.present? && restaurant.claimed_by_user_id != suggestion.user_id
          raise AlreadyClaimedError, "restaurant claimed by someone else"
        end
        restaurant.update!(
          claimed_at:         Time.current,
          claimed_by_user_id: suggestion.user_id
        )
        suggestion.update!(
          status:              "accepted",
          resolved_by_user_id: suggestion.user_id,
          resolved_at:         Time.current
        )
      end

      suggestion
    end

    # Lookup helper exposed for the mailer's dev-mode log fallback.
    def find_by_token(token)
      Suggestion.where(kind: KIND).where("payload ->> 'token' = ?", token).first
    end

    # Strict domain comparison: email's host (lowercased) must equal
    # the website's host (lowercased + leading `www.` stripped).
    # Anything else returns false; the calling Suggestion still gets
    # created — it just isn't marked auto-acceptable.
    def email_matches_website?(email, website_url)
      email_domain = email.to_s.split("@", 2).last&.downcase
      return false if email_domain.blank?
      return false if website_url.blank?

      site_host = begin
        URI.parse(website_url).host&.downcase&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        nil
      end
      return false if site_host.blank?

      email_domain == site_host
    end
  end
end
