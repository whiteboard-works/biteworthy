module Api
  module V1
    # Phase 4.3 — per-item reviews (1–5 + body + optional photo).
    #
    #   GET    /api/v1/items/:item_id/reviews   index, paginated
    #   POST   /api/v1/items/:item_id/reviews   create (multipart for photo)
    #   PATCH  /api/v1/reviews/:id              update (owner-only)
    #   DELETE /api/v1/reviews/:id              destroy (owner-only)
    #
    # Index is public (anonymous browsers see reviews on the item
    # detail page); create/update/destroy require auth and gate on
    # the review's `user_id == current_user.id`.
    class ReviewsController < BaseController
      skip_before_action :authenticate_user!, only: [:index]
      before_action :load_item,    only: [:index, :create]
      before_action :load_review,  only: [:update, :destroy]
      before_action :gate_owner!,  only: [:update, :destroy]

      DEFAULT_LIMIT = 20
      MAX_LIMIT     = 100

      def index
        limit  = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        offset = (params[:offset].presence || 0).to_i.clamp(0, 10_000)
        # Phase 4.6 — public feed shows visible (non-hidden) reviews only.
        # Flagged reviews stay public until a moderator decides; only
        # hide! removes them from the feed.
        public_scope = @item.reviews.visible
        scope        = public_scope.newest_first.includes(:user, photo_attachment: :blob).offset(offset).limit(limit)

        render json: {
          item_id: @item.id,
          reviews: scope.map { |r| serialize(r) },
          total:   public_scope.count
        }
      end

      def create
        review = @item.reviews.build(review_params)
        review.user = current_user
        if review.save
          render json: serialize(review), status: :created
        else
          render json: { error: review.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        if @review.update(review_params.except(:photo).merge(allowed_photo_update))
          render json: serialize(@review)
        else
          render json: { error: @review.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def destroy
        @review.destroy!
        head :no_content
      end

      private

      def load_item
        @item = Item.published.find(params[:item_id])
      end

      def load_review
        @review = Review.includes(:item, photo_attachment: :blob).find(params[:id])
      end

      def gate_owner!
        return if @review.user_id == current_user.id
        render json: { error: "Only the review's author can edit or delete it" }, status: :forbidden
      end

      def review_params
        params.permit(:rating, :body, :photo)
      end

      # Treat an explicit `photo: ""` in PATCH as "remove the photo".
      # Anything else only sets photo if the file param was uploaded.
      def allowed_photo_update
        return {} unless params.key?(:photo)
        if params[:photo].is_a?(ActionDispatch::Http::UploadedFile)
          { photo: params[:photo] }
        elsif params[:photo].blank?
          @review.photo.purge_later if @review.photo.attached?
          {}
        else
          {}
        end
      end

      def serialize(review)
        {
          id:           review.id,
          item_id:      review.item_id,
          user: {
            id:           review.user.id,
            handle:       review.user.handle,
            display_name: review.user.display_name
          },
          rating:       review.rating,
          body:         review.body,
          photo_url:    photo_url_for(review),
          created_at:   review.created_at,
          updated_at:   review.updated_at
        }
      end

      # Build the signed blob URL without depending on Devise's URL
      # helpers being mixed into the controller. Falls back to the
      # incoming request's base URL when PUBLIC_HOST isn't set (dev /
      # CI). Production deploys should set PUBLIC_HOST so URLs work
      # for clients fetching from a different origin.
      def photo_url_for(review)
        return nil unless review.photo.attached?
        host = ENV["PUBLIC_HOST"].presence || request.base_url
        Rails.application.routes.url_helpers.rails_blob_url(review.photo, host: host)
      end
    end
  end
end
