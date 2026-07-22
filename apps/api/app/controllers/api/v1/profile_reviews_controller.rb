module Api
  module V1
    # GET /api/v1/profile/reviews — the caller's own reviews for the
    # account page, newest first, paginated.
    #
    # Unlike the public by-handle feed (UsersController#show, visible
    # only, capped at 10), this includes the user's HIDDEN reviews and
    # tells them why (hidden_reason) — it's their own data, and a review
    # a moderator hid should still be visible to its author. Each row
    # carries item + restaurant context so the page can link back.
    #
    # Authenticated only — private data.
    class ProfileReviewsController < BaseController
      DEFAULT_LIMIT = 20
      MAX_LIMIT     = 100

      def index
        limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        offset = page_offset

        scope = current_user.reviews
                            .newest_first
                            .includes(item: :restaurant, photo_attachment: :blob)
                            .offset(offset)
                            .limit(limit)

        render json: {
          reviews: scope.map { |r| serialize(r) },
          total:   current_user.reviews.count
        }
      end

      private

      def serialize(review)
        item = review.item
        {
          id:   review.id,
          item: {
            id:   item.id,
            name: item.name,
            restaurant: {
              id:   item.restaurant_id,
              slug: item.restaurant.slug,
              name: item.restaurant.name
            }
          },
          rating:        review.rating,
          body:          review.body,
          photo_url:     photo_url_for(review),
          hidden:        review.hidden?,
          hidden_reason: review.hidden_reason,
          created_at:    review.created_at,
          updated_at:    review.updated_at
        }
      end
    end
  end
end
