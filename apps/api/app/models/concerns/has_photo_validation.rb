# Shared upload guards for models with image attachments. Each model
# declares its own `has_one_attached` and then names it here with
# `validates_image_attachments` (Item, Review, DishPhotoSubmission:
# `:photo`; Restaurant: `:logo`, `:banner`), so the size + content-type
# limits can't drift apart. User-supplied uploads are rewritten through
# Images::StripMetadata *before* attach — raw size and pixel bounds
# first, then EXIF/GPS stripped.
module HasPhotoValidation
  extend ActiveSupport::Concern

  MAX_PHOTO_BYTES = 5 * 1024 * 1024 # 5 MB
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  class_methods do
    def validates_image_attachments(*names)
      names.each do |name|
        validate { image_attachment_within_size_limit(name) }
        validate { image_attachment_is_an_allowed_type(name) }
      end
    end
  end

  private

  def image_attachment_within_size_limit(name)
    attachment = public_send(name)
    return unless attachment.attached?
    return if attachment.byte_size <= MAX_PHOTO_BYTES
    errors.add(name, "must be #{MAX_PHOTO_BYTES / 1.megabyte} MB or smaller")
  end

  def image_attachment_is_an_allowed_type(name)
    attachment = public_send(name)
    return unless attachment.attached?
    return if ALLOWED_PHOTO_TYPES.include?(attachment.content_type)
    errors.add(name, "must be one of #{ALLOWED_PHOTO_TYPES.join(', ')}")
  end
end
