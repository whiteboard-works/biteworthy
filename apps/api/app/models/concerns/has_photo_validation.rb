# Shared upload guards for models with a single `:photo` attachment
# (Item, Review). Each model still declares its own
# `has_one_attached :photo`; this centralises the size + content-type
# limits so they can't drift apart.
module HasPhotoValidation
  extend ActiveSupport::Concern

  MAX_PHOTO_BYTES = 5 * 1024 * 1024 # 5 MB
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  included do
    validate :photo_within_size_limit
    validate :photo_is_an_allowed_image_type
  end

  private

  def photo_within_size_limit
    return unless photo.attached?
    return if photo.byte_size <= MAX_PHOTO_BYTES
    errors.add(:photo, "must be #{MAX_PHOTO_BYTES / 1.megabyte} MB or smaller")
  end

  def photo_is_an_allowed_image_type
    return unless photo.attached?
    return if ALLOWED_PHOTO_TYPES.include?(photo.content_type)
    errors.add(:photo, "must be one of #{ALLOWED_PHOTO_TYPES.join(', ')}")
  end
end
