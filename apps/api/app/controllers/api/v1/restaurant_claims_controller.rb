module Api
  module V1
    # Phase 4.9 — restaurant claim flow.
    #
    #   POST   /api/v1/restaurants/:restaurant_id/claim
    #     Authenticated. Creates a Suggestion(kind: 'claim') with
    #     a verification token + email + expiry, mails the verify
    #     link out. Idempotent — re-requesting before expiry refreshes
    #     the token.
    #
    #   GET    /api/v1/restaurants/:restaurant_id/claim/verify?t=<token>
    #     Anonymous. The token alone is the credential. Marks the
    #     restaurant claimed if the token is valid + unexpired.
    class RestaurantClaimsController < BaseController
      skip_before_action :authenticate_user!, only: [:verify]

      # POST /api/v1/restaurants/:restaurant_id/claim
      def create
        restaurant = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id])
        email      = params[:email].to_s.strip.downcase

        if email.empty? || !email.include?("@")
          return render json: { error: "Email required" }, status: :unprocessable_entity
        end

        result = RestaurantClaim.request_claim(
          restaurant: restaurant,
          requester:  current_user,
          email:      email
        )
        verify_url = build_verify_url(restaurant, result.suggestion.payload["token"])
        RestaurantClaimMailer.verify_email(result.suggestion.id, verify_url).deliver_later

        render json: {
          status:           "verification_sent",
          email:            email,
          auto_acceptable:  result.auto_acceptable,
          expires_at:       result.suggestion.payload["expires_at"]
        }, status: :accepted
      rescue RestaurantClaim::AlreadyClaimedError => e
        render json: { error: e.message }, status: :conflict
      end

      # GET /api/v1/restaurants/:restaurant_id/claim/verify?t=<token>
      def verify
        suggestion = RestaurantClaim.verify(token: params[:t].to_s)
        restaurant = suggestion.subject

        render json: {
          status: "claimed",
          restaurant: {
            id:                 restaurant.id,
            slug:               restaurant.slug,
            name:               restaurant.name,
            claimed_at:         restaurant.claimed_at,
            claimed_by_user_id: restaurant.claimed_by_user_id
          }
        }
      rescue RestaurantClaim::InvalidTokenError, RestaurantClaim::ExpiredTokenError, RestaurantClaim::AlreadyClaimedError => e
        render json: { error: e.message, kind: e.class.name.demodulize }, status: :unprocessable_entity
      end

      private

      # Build the URL the email recipient clicks. The web app at
      # PUBLIC_HOST handles /restaurants/<slug>/claim?t=<token>.
      def build_verify_url(restaurant, token)
        host = ENV["PUBLIC_HOST"].presence || request.base_url
        "#{host.chomp('/')}/restaurants/#{restaurant.slug}/claim?t=#{token}"
      end
    end
  end
end
