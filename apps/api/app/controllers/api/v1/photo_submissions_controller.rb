module Api
  module V1
    # Diner dish-photo submissions.
    #
    #   POST   /api/v1/items/:item_id/photo_submissions   create (multipart)
    #   GET    /api/v1/photo_submissions                  the caller's own
    #   DELETE /api/v1/photo_submissions/:id              pending + owner only
    #
    # The photo is stripped of EXIF/GPS before it is stored. Nothing here
    # becomes Item#photo until an admin approves it. DELETE is a
    # withdrawal (status=withdrawn, bytes purged) so it still counts
    # toward the daily limit.
    class PhotoSubmissionsController < BaseController
      before_action :load_item, only: [ :create ]
      before_action :load_own_submission, only: [ :destroy ]

      DEFAULT_LIMIT = 20
      MAX_LIMIT     = 100

      def index
        scope = current_user.dish_photo_submissions
                            .newest_first
                            .includes(:item, photo_attachment: :blob)
        total = scope.count
        limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        offset = page_offset
        rows = scope.offset(offset).limit(limit)

        render json: {
          photo_submissions: rows.map { |s| DishPhotos::Serialize.diner_row(s, host: public_host) },
          pagination: { total: total, limit: limit, offset: offset }
        }
      end

      def create
        submission = DishPhotos::Submit.call(
          item: @item,
          user: current_user,
          photo: params[:photo],
          owns_rights: params[:owns_rights]
        )
        render json: DishPhotos::Serialize.diner_row(submission, host: public_host),
               status: :created
      rescue DishPhotos::Submit::RateLimited => e
        render json: { error: e.code, message: e.message }, status: :too_many_requests
      rescue Images::StripMetadata::Unprocessable => e
        render json: { error: e.code, message: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "invalid", message: e.record.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end

      def destroy
        @submission.withdraw!
        head :no_content
      rescue ActiveRecord::RecordInvalid
        render json: { error: "Only a pending submission can be withdrawn" },
               status: :unprocessable_entity
      end

      private

      def load_item
        @item = Item.published.joins(:restaurant).merge(Restaurant.published).find(params[:item_id])
      end

      def load_own_submission
        @submission = current_user.dish_photo_submissions.find(params[:id])
      end
    end
  end
end
