# frozen_string_literal: true

module DishPhotos
  # Admin decision on a pending diner photo.
  #
  # Approve-and-set prepares a new blob from the diner bytes *before*
  # taking locks, then under `item.with_lock` followed by the submission
  # lock (always that order) re-checks pending, attaches, sets
  # `photo_submission_id`, and marks the row approved in one transaction.
  # A failure leaves the submission pending and the item unchanged. The
  # previous item photo is purged only after the new blob is stored.
  class Moderate
    class NotPending < StandardError; end
    class InvalidReason < StandardError; end

    def initialize(submission, reviewer:)
      @submission = submission
      @reviewer = reviewer
    end

    def approve!(replace_item_photo:)
      if replace_item_photo
        approve_and_set!
      else
        decide!("approve_keep")
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

    def approve_and_set!
      source = @submission.photo.blob
      raise NotPending, "submission has no photo" unless source

      new_blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(source.download),
        filename: source.filename.to_s,
        content_type: source.content_type
      )
      committed = false
      old_blob_ids = []
      item = Item.find(@submission.item_id)

      begin
        item.with_lock do
          @submission.with_lock do
            raise NotPending, "already #{@submission.status}" unless @submission.pending?

            old_blob_ids = photo_blob_ids_for(item)
            item.photo.attach(new_blob)
            drop_extra_photo_attachments!(item, keep_blob_id: new_blob.id)
            item.update!(photo_submission_id: @submission.id)
            apply_decision!("approved")
          end
        end
        committed = true
      ensure
        new_blob.purge unless committed
      end

      purge_replaced_blobs(old_blob_ids - [ new_blob.id ])
      preprocess_variants!(item.reload)
    end

    def decide!(status)
      item = Item.find(@submission.item_id)
      item.with_lock do
        @submission.with_lock do
          raise NotPending, "already #{@submission.status}" unless @submission.pending?

          apply_decision!(status)
        end
      end
    end

    def apply_decision!(status)
      @submission.update!(
        status: status,
        reviewed_by: @reviewer,
        reviewed_at: Time.current,
        rejection_reason: nil
      )
    end

    def photo_blob_ids_for(item)
      ActiveStorage::Attachment.where(record: item, name: "photo").pluck(:blob_id)
    end

    def drop_extra_photo_attachments!(item, keep_blob_id:)
      ActiveStorage::Attachment.where(record: item, name: "photo")
                               .where.not(blob_id: keep_blob_id)
                               .delete_all
    end

    def purge_replaced_blobs(blob_ids)
      ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later)
    end

    def preprocess_variants!(item)
      return unless item.photo.attached?

      item.photo.variant(:card).processed
    rescue StandardError => e
      Rails.logger.warn("Variant preprocessing failed: #{e.class} #{e.message}")
    end
  end
end
