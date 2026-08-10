module Api
  module V1
    module Admin
      # Review moderation for the web admin (twin of the Avo
      # Hide/Unhide/MarkSpam actions — the logic is Review#hide!/#unhide!).
      #
      #   GET  /api/v1/admin/reviews?visibility=flagged|hidden|visible|all
      #   POST /api/v1/admin/reviews/:id/hide    { reason: <HIDDEN_REASONS> }
      #   POST /api/v1/admin/reviews/:id/unhide
      #
      # "Mark spam" is just hide with reason "spam" — the UI offers it
      # as a preset, not a separate endpoint.
      class ReviewsController < BaseController
        include Deletable
        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        VISIBILITY_SCOPES = {
          "flagged" => :awaiting_moderation,
          "hidden"  => :hidden,
          "visible" => :visible,
          "all"     => :all
        }.freeze

        def index
          scope_name = VISIBILITY_SCOPES.fetch(params[:visibility].to_s.presence || "flagged", nil)
          unless scope_name
            render json: { error: "invalid_visibility", allowed: VISIBILITY_SCOPES.keys },
                   status: :unprocessable_entity
            return
          end

          reviews = Review.public_send(scope_name)
                          .order(created_at: :desc)
                          .includes(:user, { item: :restaurant }, photo_attachment: :blob)
          reviews = reviews.where(item_id: params[:item_id]) if params[:item_id].present?
          reviews = reviews.where(user_id: params[:user_id]) if params[:user_id].present?

          total  = reviews.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset

          render json: {
            reviews: reviews.limit(limit).offset(offset).map { |r| serialize_review(r) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def hide
          review = Review.find(params[:id])
          reason = params[:reason].to_s
          unless Review::HIDDEN_REASONS.include?(reason)
            render json: { error: "invalid_reason", allowed: Review::HIDDEN_REASONS },
                   status: :unprocessable_entity
            return
          end

          review.hide!(reason: reason)
          render json: serialize_review(review)
        end

        def unhide
          review = Review.find(params[:id])
          review.unhide!
          render json: serialize_review(review)
        end

        # Hard only, on purpose — see Deletable. Hiding a review is
        # #hide, which records *why*; a delete that had to pick a
        # reason from that list would be recording a lie.
        def destroy
          authorize_hard_delete! or return
          unless hard_delete_requested?
            return render_soft_delete_unsupported(
              use: "POST /api/v1/admin/reviews/:id/hide with a reason"
            )
          end

          review = Review.find(params[:id])
          review.destroy!
          render_hard_deleted(review)
        end

        private

        def serialize_review(review)
          item = review.item
          {
            id:            review.id,
            rating:        review.rating,
            body:          review.body,
            photo_url:     photo_url_for(review),
            created_at:    review.created_at,
            flagged_at:    review.flagged_at,
            hidden_at:     review.hidden_at,
            hidden_reason: review.hidden_reason,
            user: {
              id:           review.user.id,
              handle:       review.user.handle,
              display_name: review.user.display_name
            },
            item: {
              id:   item.id,
              name: item.name,
              restaurant: {
                id:   item.restaurant.id,
                name: item.restaurant.name,
                slug: item.restaurant.slug
              }
            }
          }
        end
      end
    end
  end
end
