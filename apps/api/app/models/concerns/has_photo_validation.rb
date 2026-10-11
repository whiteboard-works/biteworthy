# Shared upload guards for models with image attachments. Each model
# still declares its own `has_one_attached`; this centralises the size +
# content-type limits so they can't drift apart. Including the concern
# guards `:photo` (Item, Review, DishPhotoSubmission); a model with other
# attachment names calls `validates_image_attachments` for them
# (Restaurant: `:logo`, `:banner`). Diner-facing uploads (reviews and
# dish submissions) are rewritten through Images::StripMetadata *before*
# attach — raw size and pixel bounds first, then EXIF/GPS stripped.
module HasPhotoValidation
  extend ActiveSupport::Concern

  MAX_PHOTO_BYTES = 5 * 1024 * 1024 # 5 MB
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  included do
    validates_image_attachments :photo
  end

  class_methods do
    def validates_image_attachments(*names)
      names.each do |name|
        validate { image_attachment_within_size_limit(name) }
        validate { image_attachment_is_an_allowed_type(name) }
      end
    end
  end

  private

  # The include usually precedes `has_one_attached`, and Restaurant has
  # no `:photo` at all, so the attachment is looked up at validation
  # time rather than when the validator is declared.
  def image_attachment(name)
    self.class.reflect_on_attachment(name) && public_send(name)
  end

  def image_attachment_within_size_limit(name)
    attachment = image_attachment(name)
    return unless attachment&.attached?
    return if attachment.byte_size <= MAX_PHOTO_BYTES
    errors.add(name, "must be #{MAX_PHOTO_BYTES / 1.megabyte} MB or smaller")
  end

  def image_attachment_is_an_allowed_type(name)
    attachment = image_attachment(name)
    return unless attachment&.attached?
    return if ALLOWED_PHOTO_TYPES.include?(attachment.content_type)
    errors.add(name, "must be one of #{ALLOWED_PHOTO_TYPES.join(', ')}")
  end
end
