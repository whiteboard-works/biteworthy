# frozen_string_literal: true

module DishPhotos
  # Admin decision on a pending diner photo. The row is locked for the
  # duration so concurrent approve/reject cannot both apply. Approve-and-set
  # copies the stripped image onto Item#photo through Admin::ItemEditor
  # (the same path as PATCH /admin/items/:id) so the WebP variants
  # generate, then records the submission as the photo's source for the
  # dish-page credit. approve_keep marks it accepted without replacing
  # the current dish photo. Reject purges the stored bytes.
  class Moderate
    class NotPending < StandardError; end
    class InvalidReason < StandardError; end

    def initialize(submission, reviewer:)
      @submission = submission
      @reviewer = reviewer
    end

    def approve!(replace_item_photo:)
      @submission.with_lock do
        raise NotPending, "already #{@submission.status}" unless @submission.pending?

        if replace_item_photo
          copy_onto_item!
          status = "approved"
        else
          status = "approve_keep"
        end

        @submission.update!(
          status: status,
          reviewed_by: @reviewer,
          reviewed_at: Time.current,
          rejection_reason: nil
        )
      end
      @submission
    end

    def reject!(reason:)
      reason = reason.to_s
      unless DishPhotoSubmission::REJECTION_REASONS.include?(reason)
        raise InvalidReason, reason
      end

      @submission.with_lock do
        raise NotPending, "already #{@submission.status}" unless @submission.pending?

        @submission.update!(
          status: "rejected",
          rejection_reason: reason,
          reviewed_by: @reviewer,
          reviewed_at: Time.current
        )
        @submission.photo.purge if @submission.photo.attached?
      end
      @submission
    end

    private

    def copy_onto_item!
      item = @submission.item
      upload = UploadedBlob.new(@submission.photo.blob)
      begin
        Admin::ItemEditor.new(item).call(photo: upload)
      ensure
        upload.close
      end
      item.update!(photo_submission_id: @submission.id)
    end
  end
end
