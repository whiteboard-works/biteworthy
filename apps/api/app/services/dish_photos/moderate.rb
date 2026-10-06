# frozen_string_literal: true

module DishPhotos
  # Admin decision on a pending diner photo. Approve-and-set copies the
  # stripped image onto Item#photo through Admin::ItemEditor (the same
  # path as PATCH /admin/items/:id) so the WebP variants generate, then
  # records the submission as the photo's source for the dish-page
  # credit. Approve-without-replacing keeps the current dish photo.
  class Moderate
    class NotPending < StandardError; end
    class InvalidReason < StandardError; end

    def initialize(submission, reviewer:)
      @submission = submission
      @reviewer = reviewer
    end

    def approve!(replace_item_photo:)
      raise NotPending, "already #{@submission.status}" unless @submission.pending?

      item = @submission.item
      if replace_item_photo
        upload = UploadedBlob.new(@submission.photo.blob)
        begin
          Admin::ItemEditor.new(item).call(photo: upload)
        ensure
          upload.close
        end
        item.update!(photo_submission_id: @submission.id)
      end

      @submission.update!(
        status: "approved",
        reviewed_by: @reviewer,
        reviewed_at: Time.current,
        rejection_reason: nil
      )
      @submission
    end

    def reject!(reason:)
      raise NotPending, "already #{@submission.status}" unless @submission.pending?
      reason = reason.to_s
      unless DishPhotoSubmission::REJECTION_REASONS.include?(reason)
        raise InvalidReason, reason
      end

      @submission.update!(
        status: "rejected",
        rejection_reason: reason,
        reviewed_by: @reviewer,
        reviewed_at: Time.current
      )
      @submission
    end
  end
end
