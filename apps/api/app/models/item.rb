class Item < ApplicationRecord
  STATUSES   = %w[draft published removed].freeze
  CONFIDENCE = %w[confirmed suggested inferred].freeze

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

  validates :name, presence: true
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE }

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
end
