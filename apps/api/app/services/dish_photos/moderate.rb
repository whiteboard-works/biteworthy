# frozen_string_literal: true

module DishPhotos
  # Admin decision on a pending diner photo. The row is locked for the
  # status change so concurrent approve/reject cannot both apply.
  #
  # Approve-and-set copies bytes onto Item#photo *after* that lock
  # commits. ActiveStorage uploads on after_commit; doing the copy
  # inside with_lock nested the upload in the lock transaction, so the
  # tempfile was gone (or the IO closed) before the bytes landed. A
  # previous staff photo was then purged against a missing replacement.
  # Variants generate from the new blob once it is on disk.
  class Moderate
    class NotPending < StandardError; end
    class InvalidReason < StandardError; end

    def initialize(submission, reviewer:)
      @submission = submission
      @reviewer = reviewer
    end

    def approve!(replace_item_photo:)
      should_copy = false
      @submission.with_lock do
        raise NotPending, "already #{@submission.status}" unless @submission.pending?

        should_copy = replace_item_photo
        @submission.update!(
          status: should_copy ? "approved" : "approve_keep",
          reviewed_by: @reviewer,
          reviewed_at: Time.current,
          rejection_reason: nil
        )
      end
      copy_onto_item! if should_copy
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
      source = @submission.photo.blob
      raise NotPending, "submission has no photo" unless source

      bytes = source.download
      item.photo.attach(
        io: StringIO.new(bytes),
        filename: source.filename.to_s,
        content_type: source.content_type
      )
      item.update!(photo_submission_id: @submission.id)
      preprocess_variants!(item)
    end

    def preprocess_variants!(item)
      return unless item.photo.attached?

      item.photo.variant(:card).processed
    rescue StandardError => e
      Rails.logger.warn("Variant preprocessing failed: #{e.class} #{e.message}")
    end
  end
end
