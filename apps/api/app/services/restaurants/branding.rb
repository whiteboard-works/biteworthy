# frozen_string_literal: true

module Restaurants
  # The one writer for a restaurant's logo and banner. Two doors call it:
  # `PATCH /restaurants/:id/branding` (multipart files from web) and the
  # `set_restaurant_branding` tool (signed blob ids from POST /attachments).
  #
  # Who may call it is the whole security model: the restaurant's verified
  # owner (`claimed_by_user_id`, set by the emailed claim token), an
  # admin, or — while the restaurant is still a draft — the community
  # member who created it, the same rule the scan door applies
  # (`Ingestion::StartRun.can_target?`). Publishing ends the creator's
  # say: from then on it is the owner's or an admin's.
  #
  # Every image goes through Images::StripMetadata, so an owner's phone
  # photo lands without EXIF/GPS and over the same size/type limits as a
  # diner photo. Replacing a has_one attachment purges the old blob
  # (ActiveStorage's default `dependent: :purge_later`), so nothing is
  # orphaned.
  module Branding
    class Forbidden < StandardError
      def initialize(restaurant)
        super("Only the verified owner of #{restaurant.name}, an admin, or (while it is a draft) " \
              "the person who added it can change its branding.")
      end
    end

    VARIANTS = { logo: :thumb, banner: :card }.freeze

    module_function

    def authorize!(user, restaurant)
      return restaurant if user&.is_admin?
      return restaurant if restaurant.claimed_by_user_id.present? && restaurant.claimed_by_user_id == user&.id
      return restaurant if restaurant.status == "draft" && restaurant.created_by_user_id.present? &&
                           restaurant.created_by_user_id == user&.id

      raise Forbidden, restaurant
    end

    # `logo` / `banner`: an uploaded file or an ActiveStorage::Blob, or
    # nil to leave that image alone. `remove_*` wins over an upload.
    # Images are assigned, not attached, so the record is validated and
    # written once however many changed. Raises
    # Images::StripMetadata::Unprocessable for a bad image and
    # ActiveRecord::RecordInvalid when the stored copy fails validation.
    def apply!(restaurant, logo: nil, banner: nil, remove_logo: false, remove_banner: false)
      changes = { logo: [ logo, remove_logo ], banner: [ banner, remove_banner ] }
      restaurant.transaction do
        changes.each do |name, (source, remove)|
          if remove
            attachment = restaurant.public_send(name)
            attachment.purge_later if attachment.attached?
          elsif source
            restaurant.public_send("#{name}=", stripped(source))
          end
        end
        restaurant.save!
      end
      restaurant
    end

    # Signed URL for the served variant of a logo or banner, or nil when
    # nothing is attached. The original upload is never served.
    def variant_url(attachment, variant, host:)
      return nil unless attachment.attached?

      Rails.application.routes.url_helpers.rails_representation_url(attachment.variant(variant), host: host)
    end

    def stripped(source)
      identity = Images::AttachPhoto.identity(source)
      result = Images::StripMetadata.call(source, filename: identity[:filename], content_type: identity[:content_type])
      { io: result.io, filename: result.filename, content_type: result.content_type }
    end
    private_class_method :stripped
  end
end
