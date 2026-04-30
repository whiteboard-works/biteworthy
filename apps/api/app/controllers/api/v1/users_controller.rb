module Api
  module V1
    # Phase 4.7 — public user profile lookup by handle.
    #
    # GET /api/v1/users/:handle returns a small *public* payload —
    # display_name, handle, member_since, recent (visible) reviews
    # and a count of restaurants they've reviewed at. Sensitive
    # fields (email, dietary profile, overrides, jti, sign_in
    # timestamps) are intentionally absent.
    #
    # Anonymous access is intentional — the page is meant to be
    # linkable. Authenticated callers see the same payload; nothing
    # changes based on identity (Phase 4.8 history stays on the
    # private /api/v1/profile/history endpoint).
    class UsersController < BaseController
      skip_before_action :authenticate_user!, only: [:show]

      RECENT_REVIEW_LIMIT = 10

      def show
        user = User.find_by!(handle: params[:handle])
        recent_reviews = user.reviews.visible
                            .includes(item: :restaurant, photo_attachment: :blob)
                            .order(created_at: :desc)
                            .limit(RECENT_REVIEW_LIMIT)

        # One COUNT DISTINCT — much cheaper than loading restaurants.
        # Hidden reviews are excluded so the public stat stays accurate.
        restaurants_reviewed_count = user.reviews.visible.joins(:item).distinct.count("items.restaurant_id")

        render json: {
          handle:                     user.handle,
          display_name:               user.display_name,
          member_since:               user.created_at,
          reviews_count:              user.reviews.visible.count,
          restaurants_reviewed_count: restaurants_reviewed_count,
          recent_reviews:             recent_reviews.map { |r| serialize_review(r) }
        }
      end

      private

      def serialize_review(review)
        item = review.item
        {
          id:           review.id,
          item: {
            id:   item.id,
            name: item.name,
            restaurant: {
              id:   item.restaurant_id,
              slug: item.restaurant.slug,
              name: item.restaurant.name
            }
          },
          rating:     review.rating,
          body:       review.body,
          photo_url:  photo_url_for(review),
          created_at: review.created_at
        }
      end

      def photo_url_for(review)
        return nil unless review.photo.attached?
        host = ENV["PUBLIC_HOST"].presence || request.base_url
        Rails.application.routes.url_helpers.rails_blob_url(review.photo, host: host)
      end
    end
  end
end
