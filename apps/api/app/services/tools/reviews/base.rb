# frozen_string_literal: true

module Tools
  module Reviews
    # Shared loading + serialization for the review tools.
    #
    # `list_reviews` is public, so this base stays at the default
    # `:public` audience and each write tool raises its own.
    class Base < Tools::Base
      class << self
        def find_review!(review_id)
          Review.includes(:user, item: :restaurant).find(review_id)
        end

        # Editing and deleting are author-only. Unlike the ingestion
        # tools, Forbidden rather than NotFound is right here: reviews
        # are a public feed, so the review's existence is not a secret.
        def authorize_author!(context, review)
          user = context.user!
          return review if review.user_id == user.id

          raise Errors::Forbidden, "Only the review's author can edit or delete it."
        end

        def review_row(review, include_hidden_state: false)
          row = {
            id:         review.id,
            item_id:    review.item_id,
            rating:     review.rating,
            body:       untrusted(review.body),
            author:     { handle: review.user.handle, display_name: review.user.display_name },
            created_at: review.created_at
          }
          return row unless include_hidden_state

          row.merge(hidden: review.hidden?, hidden_reason: review.hidden_reason)
        end
      end
    end
  end
end
