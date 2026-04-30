class Item < ApplicationRecord
  STATUSES   = %w[draft published removed].freeze
  CONFIDENCE = %w[confirmed suggested inferred].freeze

  # Phase 4.11.3 — same shape as Review#photo so the same upload paths
  # and any future shared helpers (resize variants, etc.) work for both.
  MAX_PHOTO_BYTES = 5 * 1024 * 1024
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  belongs_to :restaurant
  belongs_to :menu_section, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :item_variants,    dependent: :destroy
  has_many :item_modifiers,   dependent: :destroy
  has_many :item_ingredients, dependent: :destroy
  has_many :ingredients, through: :item_ingredients
  has_many :item_tags,        dependent: :destroy
  has_many :tags,        through: :item_tags
  has_many :reviews,          dependent: :destroy
  has_many :user_item_overrides, dependent: :destroy

  has_one_attached :photo

  validates :name, presence: true
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE }
  validate  :photo_within_size_limit
  validate  :photo_is_an_allowed_image_type

  scope :published, -> { where(status: "published") }

  # Hard filter: items where ANY ingredient_id is in `avoid_ids`.
  # Uses the GIN index on ingredient_ids via the && (overlap) operator.
  scope :without_ingredients, ->(avoid_ids) {
    return all if avoid_ids.blank?
    where.not("ingredient_ids && ARRAY[?]::uuid[]", avoid_ids)
  }

  scope :without_tags, ->(avoid_ids) {
    return all if avoid_ids.blank?
    where.not("tag_ids && ARRAY[?]::uuid[]", avoid_ids)
  }

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
