# frozen_string_literal: true

module DishPhotos
  # Data fix for Item#photo rows that raced two attaches and kept both.
  # Keeps the attachment whose blob checksum matches the credited
  # submission, or the newest attachment when there is no credit match.
  # Idempotent: a second run finds nothing with COUNT(*) > 1.
  class CollapseDuplicatePhotos
    def self.call(dry_run: true)
      new(dry_run: dry_run).call
    end

    def initialize(dry_run:)
      @dry_run = dry_run
    end

    def call
      item_ids = duplicate_item_ids
      details = item_ids.filter_map { |item_id| collapse_item(item_id) }

      {
        dry_run: @dry_run,
        items_examined: item_ids.size,
        items_collapsed: details.size,
        attachments_purged: details.sum { |row| row[:purged_blob_ids].size },
        details: details
      }
    end

    private

    def duplicate_item_ids
      ActiveStorage::Attachment.where(record_type: "Item", name: "photo")
                               .group(:record_id)
                               .having("COUNT(*) > 1")
                               .pluck(:record_id)
    end

    def collapse_item(item_id)
      Item.transaction do
        item = Item.lock.find_by(id: item_id)
        return if item.nil?

        attachments = ActiveStorage::Attachment.where(record: item, name: "photo")
                                               .includes(:blob)
                                               .to_a
        return if attachments.size <= 1

        keeper = keeper_for(item, attachments)
        extras = attachments.reject { |attachment| attachment.id == keeper.id }
        extras.each(&:purge) unless @dry_run

        {
          item_id: item.id,
          kept_blob_id: keeper.blob_id,
          purged_blob_ids: extras.map(&:blob_id)
        }
      end
    end

    def keeper_for(item, attachments)
      credited = credited_attachment(item, attachments)
      return credited if credited

      attachments.max_by { |attachment| [ attachment.created_at, attachment.id ] }
    end

    def credited_attachment(item, attachments)
      return if item.photo_submission_id.blank?

      submission = DishPhotoSubmission.find_by(id: item.photo_submission_id)
      return unless submission&.photo&.attached?

      checksum = submission.photo.blob.checksum
      attachments.find { |attachment| attachment.blob.checksum == checksum }
    end
  end
end
