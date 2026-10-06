module Api
  module V1
    module Admin
      # Diner dish-photo queue for the web admin + MCP twin.
      #
      #   GET  /api/v1/admin/photo_submissions?status=pending|approved|rejected|all
      #   POST /api/v1/admin/photo_submissions/:id/approve  { replace_item_photo: true|false }
      #   POST /api/v1/admin/photo_submissions/:id/reject   { reason: <REJECTION_REASONS> }
      class PhotoSubmissionsController < BaseController
        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        STATUS_SCOPES = {
          "pending"  => :pending,
          "approved" => :approved,
          "rejected" => :rejected,
          "all"      => :all
        }.freeze

        def index
          scope_name = STATUS_SCOPES.fetch(params[:status].to_s.presence || "pending", nil)
          unless scope_name
            render json: { error: "invalid_status", allowed: STATUS_SCOPES.keys },
                   status: :unprocessable_entity
            return
          end

          submissions = DishPhotoSubmission.public_send(scope_name)
                                           .newest_first
                                           .includes(:user, :reviewed_by,
                                                     { item: [ :restaurant, { photo_attachment: :blob } ] },
                                                     photo_attachment: :blob)
          submissions = submissions.where(item_id: params[:item_id]) if params[:item_id].present?

          total  = submissions.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset

          render json: {
            photo_submissions: submissions.limit(limit).offset(offset).map { |s|
              DishPhotos::Serialize.admin_row(s, host: public_host)
            },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def approve
          submission = DishPhotoSubmission.includes(:item, photo_attachment: :blob).find(params[:id])
          replace = if params.key?(:replace_item_photo)
            ActiveModel::Type::Boolean.new.cast(params[:replace_item_photo])
          else
            !submission.item.photo.attached?
          end

          DishPhotos::Moderate.new(submission, reviewer: current_user).approve!(replace_item_photo: replace)
          render json: DishPhotos::Serialize.admin_row(submission.reload, host: public_host)
        rescue DishPhotos::Moderate::NotPending => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject
          submission = DishPhotoSubmission.find(params[:id])
          DishPhotos::Moderate.new(submission, reviewer: current_user)
                              .reject!(reason: params[:reason])
          render json: DishPhotos::Serialize.admin_row(submission, host: public_host)
        rescue DishPhotos::Moderate::NotPending => e
          render json: { error: e.message }, status: :unprocessable_entity
        rescue DishPhotos::Moderate::InvalidReason => e
          render json: { error: "invalid_reason", value: e.message,
                         allowed: DishPhotoSubmission::REJECTION_REASONS },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
