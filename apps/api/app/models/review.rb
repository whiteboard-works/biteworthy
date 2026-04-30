class Review < ApplicationRecord
  # Phase 4.3 — adds the optional photo + content/size validation. The
  # rating + body columns shipped in Phase 0; this only changes the
  # behavior, no migration.
  MAX_PHOTO_BYTES = 5 * 1024 * 1024 # 5 MB
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  belongs_to :user
  belongs_to :item

  has_one_attached :photo

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validate  :photo_within_size_limit
  validate  :photo_is_an_allowed_image_type

  scope :newest_first, -> { order(created_at: :desc) }

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
