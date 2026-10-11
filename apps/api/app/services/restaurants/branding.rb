# frozen_string_literal: true

module Restaurants
  # The one writer for a restaurant's logo and banner. Two doors call it:
  # `PATCH /restaurants/:id/branding` (multipart files from web) and the
  # `set_restaurant_branding` tool (signed blob ids from POST /attachments).
  #
  # Who may call it is the whole security model: the restaurant's verified
  # owner (`claimed_by_user_id`, set by the emailed claim token), an
  # admin, or — while the restaurant is still a draft — the community
  # member who created it (`Restaurant#draft_created_by?`, the scan
  # door's rule too). Publishing ends the creator's say: from then on it
  # is the owner's or an admin's.
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

    # The stored shape and largest stored size of each slot. Web shows the
    # logo as a 48–56px square and the banner full-width at 8:3, so an
    # upload is cropped to that shape (Images::Fit) rather than trimmed
    # by CSS. The served variants in Restaurant use the same sizes.
    SIZES = { logo: [ 400, 400 ], banner: [ 1600, 600 ] }.freeze
    ASPECTS = { logo: "1:1", banner: "8:3" }.freeze

    module_function

    def authorize!(user, restaurant)
      return restaurant if user&.is_admin?
      return restaurant if restaurant.claimed_by_user_id.present? && restaurant.claimed_by_user_id == user&.id
      return restaurant if restaurant.draft_created_by?(user)

      raise Forbidden, restaurant
    end

    # `logo` / `banner`: an uploaded file or an ActiveStorage::Blob, or
    # nil to leave that image alone. `remove_*` wins over an upload.
    # `logo_crop` / `banner_crop`: an Images::Fit crop (anchor and/or
    # box); without one an off-shape image is center-cropped.
    # Images are assigned, not attached, so the record is validated and
    # written once however many changed. Returns what Fit did to each new
    # image (source size, crop box, stored size). Raises
    # Images::StripMetadata::Unprocessable for a bad image or crop and
    # ActiveRecord::RecordInvalid when the stored copy fails validation.
    def apply!(restaurant, logo: nil, banner: nil, remove_logo: false, remove_banner: false,
               logo_crop: nil, banner_crop: nil)
      changes = { logo: [ logo, remove_logo, logo_crop ], banner: [ banner, remove_banner, banner_crop ] }
      changes.each do |name, (source, remove, crop)|
        next if crop.blank? || (source && !remove)

        raise Images::Fit::InvalidCrop, "#{name}_crop needs a new #{name} image to crop"
      end

      # Image work happens before the transaction, so no connection is
      # held open while libvips decodes and encodes.
      fits = changes.filter_map do |name, (source, remove, crop)|
        [ name, fitted(source, name, crop) ] if source && !remove
      end.to_h

      restaurant.transaction do
        changes.each do |name, (_, remove, _)|
          if remove
            attachment = restaurant.public_send(name)
            attachment.purge_later if attachment.attached?
          elsif (filename, fit = fits[name])
            restaurant.public_send("#{name}=", { io: fit.io, filename:, content_type: fit.content_type })
          end
        end
        restaurant.save!
      end
      fits.transform_values do |(_, fit)|
        { source: fit.source, crop: fit.crop, stored: fit.stored, cropped: fit.cropped? }
      end
    end

    # Signed URL for the served variant of a logo or banner, or nil when
    # nothing is attached. The original upload is never served.
    def variant_url(attachment, variant, host:)
      return nil unless attachment.attached?

      Rails.application.routes.url_helpers.rails_representation_url(attachment.variant(variant), host: host)
    end

    # StripMetadata first (autorotate, EXIF/GPS, size bounds), then Fit,
    # which keeps the stripped copy's format and so its filename.
    def fitted(source, name, crop)
      identity = Images::AttachPhoto.identity(source)
      stripped = Images::StripMetadata.call(source, filename: identity[:filename], content_type: identity[:content_type])
      [ stripped.filename, Images::Fit.call(stripped.io, content_type: stripped.content_type, size: SIZES.fetch(name), crop:) ]
    end
    private_class_method :fitted
  end
end
