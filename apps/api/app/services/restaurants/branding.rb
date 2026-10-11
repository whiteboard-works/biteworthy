# frozen_string_literal: true

module Restaurants
  # The one writer for a restaurant's logo and banner. Two doors call it:
  # `PATCH /restaurants/:id/branding` (multipart files from web) and the
  # `set_restaurant_branding` tool (signed blob ids from POST /attachments).
  #
  # Who may call it is the whole security model: the restaurant's verified
  # owner (`claimed_by_user_id`, set by the emailed claim token) or an
  # admin. Same gate as resolving suggestions.
  #
  # Every image goes through Images::AttachPhoto, so an owner's phone
  # photo lands without EXIF/GPS and over the same size/type limits as a
  # diner photo. A replaced blob is purged rather than left orphaned.
  module Branding
    class Forbidden < StandardError
      def initialize(restaurant)
        super("Only the verified owner of #{restaurant.name} or an admin can change its branding.")
      end
    end

    ATTACHMENTS = %i[logo banner].freeze

    module_function

    def authorize!(user, restaurant)
      return restaurant if user&.is_admin?
      return restaurant if restaurant.claimed_by_user_id.present? && restaurant.claimed_by_user_id == user&.id

      raise Forbidden, restaurant
    end

    # `logo` / `banner`: an uploaded file or an ActiveStorage::Blob, or
    # nil to leave that image alone. `remove_*` wins over an upload.
    # Replacing a has_one attachment purges the old blob (ActiveStorage's
    # default `dependent: :purge_later`), so nothing is orphaned.
    # Raises Images::StripMetadata::Unprocessable for a bad image and
    # ActiveRecord::RecordInvalid when the stored copy fails validation.
    def apply!(restaurant, logo: nil, banner: nil, remove_logo: false, remove_banner: false)
      changes = { logo: [ logo, remove_logo ], banner: [ banner, remove_banner ] }
      restaurant.transaction do
        changes.each do |name, (source, remove)|
          if remove
            attachment = restaurant.public_send(name)
            attachment.purge_later if attachment.attached?
          elsif source
            Images::AttachPhoto.call(restaurant, source, name: name)
          end
        end
        restaurant.save!
      end
      restaurant
    end
  end
end
