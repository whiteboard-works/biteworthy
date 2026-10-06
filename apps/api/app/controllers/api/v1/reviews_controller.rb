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
    #
    # Review photos (and dish-photo offers) are rewritten through
    # Images::StripMetadata before attach — no EXIF/GPS on the public
    # blob. Offering the photo as the dish photo is best-effort: a
    # rate-limit on the offer does not roll back the review.
    class ReviewsController < BaseController
      skip_before_action :authenticate_user!, only: [:index]
      before_action :load_item,    only: [:index, :create]
      before_action :load_review,  only: [:update, :destroy, :report]
      before_action :gate_owner!,  only: [:update, :destroy]

      DEFAULT_LIMIT = 20
      MAX_LIMIT     = 100

      def index
        limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        offset = page_offset
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
        offering = offering_dish_photo?
        if offering && !photo_upload?(params[:photo])
          render json: { error: "photo_required",
                         message: "A photo is required to offer it as the dish photo" },
                 status: :unprocessable_entity
          return
        end
        if offering && !DishPhotos::OwnsRights.accepted?(params[:owns_rights])
          render json: { error: "owns_rights",
                         message: "You must confirm you took this photo to offer it as the dish photo" },
                 status: :unprocessable_entity
          return
        end

        review = @item.reviews.build(review_params)
        review.user = current_user
        Images::AttachPhoto.call(review, params[:photo]) if photo_upload?(params[:photo])

        unless review.save
          render json: { error: review.errors.full_messages.join(", ") }, status: :unprocessable_entity
          return
        end

        payload = serialize(review)
        payload[:photo_offer] = offer_dish_photo(review) if offering
        render json: payload, status: :created
      rescue Images::StripMetadata::Unprocessable => e
        render json: { error: e.code, message: e.message }, status: :unprocessable_entity
      end

      def update
        Review.transaction do
          @review.assign_attributes(review_params)
          @review.validate!
          apply_photo_change!
          @review.save!
        end
        render json: serialize(@review)
      rescue ActiveRecord::RecordInvalid
        render json: { error: @review.errors.full_messages.join(", ") }, status: :unprocessable_entity
      rescue Images::StripMetadata::Unprocessable => e
        render json: { error: e.code, message: e.message }, status: :unprocessable_entity
      end

      def destroy
        @review.destroy!
        head :no_content
      end

      # POST /api/v1/reviews/:id/report — legal remediation E8.
      # Any signed-in reader can report a review; it routes into the
      # existing admin moderation queue (sets flagged_at, doesn't hide).
      # Idempotent, so a re-report is a harmless no-op.
      def report
        @review.report!
        head :no_content
      end

      private

      # Published dish AND published restaurant. `write_review` has scoped
      # it that way since M3a; here it was `Item.published` alone, so a
      # dish at a restaurant that was never published — or was pulled —
      # stayed reviewable over REST and not over MCP.
      def load_item
        @item = Item.published.joins(:restaurant).merge(Restaurant.published).find(params[:item_id])
      end

      def load_review
        @review = Review.includes(:item, photo_attachment: :blob).find(params[:id])
      end

      def gate_owner!
        return if @review.user_id == current_user.id
        render json: { error: "Only the review's author can edit or delete it" }, status: :forbidden
      end

      def review_params
        params.permit(:rating, :body)
      end

      def apply_photo_change!
        if photo_upload?(params[:photo])
          Images::AttachPhoto.call(@review, params[:photo])
        elsif params.key?(:photo) && params[:photo].blank?
          @review.photo.purge if @review.photo.attached?
        end
      end

      def photo_upload?(value)
        value.respond_to?(:tempfile)
      end

      def offering_dish_photo?
        ActiveModel::Type::Boolean.new.cast(params[:offer_as_dish_photo])
      end

      def offer_dish_photo(review)
        submission = DishPhotos::Submit.call(
          item: @item,
          user: current_user,
          photo: params[:photo],
          owns_rights: params[:owns_rights],
          review: review
        )
        { status: "pending", id: submission.id }
      rescue DishPhotos::Submit::RateLimited => e
        { status: "rate_limited", code: e.code, message: e.message }
      rescue Images::StripMetadata::Unprocessable => e
        { status: "failed", code: e.code, message: e.message }
      rescue ActiveRecord::RecordInvalid => e
        { status: "failed", code: "invalid", message: e.record.errors.full_messages.join(", ") }
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
    end
  end
end
