# frozen_string_literal: true

module DishPhotos
  module Serialize
    module_function

    def diner_row(submission, host:)
      {
        id:                submission.id,
        item_id:           submission.item_id,
        status:            submission.status,
        rejection_reason:  submission.rejection_reason,
        owns_rights:       submission.owns_rights,
        review_id:         submission.review_id,
        photo_url:         photo_url(submission, host:),
        credit_name:       submission.credit_name,
        created_at:        submission.created_at,
        reviewed_at:       submission.reviewed_at
      }
    end

    def admin_row(submission, host:)
      item = submission.item
      restaurant = item.restaurant
      diner_row(submission, host:).merge(
        photo_url: variant_url(submission.photo, :thumb, host:),
        user: {
          id:           submission.user&.id,
          handle:       submission.user&.handle,
          display_name: submission.user&.display_name
        },
        item: {
          id:   item.id,
          name: item.name,
          photo_url: variant_url(item.photo, :thumb, host:),
          restaurant: {
            id:   restaurant.id,
            name: restaurant.name,
            slug: restaurant.slug
          }
        }
      )
    end

    def photo_url(record, host:)
      return nil if host.blank?
      return nil unless record.photo.attached?

      Rails.application.routes.url_helpers.rails_blob_url(record.photo, host: host)
    end

    def variant_url(attachment, variant, host:)
      return nil if host.blank?
      return nil unless attachment.attached?

      if attachment.variable?
        Rails.application.routes.url_helpers.rails_representation_url(
          attachment.variant(variant), host: host
        )
      else
        Rails.application.routes.url_helpers.rails_blob_url(attachment, host: host)
      end
    end
  end
end
