class Item < ApplicationRecord
  include HasPhotoValidation

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
  has_many :favorite_items,   dependent: :destroy
  # A staged row records what the pipeline proposed and what a human
  # decided about it — history about the *run*, which outlives the menu
  # item that decision produced. `matched_item_id` already nullifies at
  # the database level for the same reason; `item_id` had no
  # association at all, so destroying a promoted item raised
  # InvalidForeignKey.
  has_many :ingestion_items,  dependent: :nullify

  has_one_attached :photo

  validates :name, presence: true
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE }

  scope :published, -> { where(status: "published") }

  # `item.ingredient_ids` / `item.tag_ids` resolve to the has_many-through
  # readers, which SHADOW the identically-named denormalized columns and
  # cost a query per item unless the association is preloaded. These read
  # the columns the join callbacks keep in sync — free, and the same
  # arrays `Cities::RestaurantRanking` and `TasteScoring` hit in SQL.
  # Read paths that don't already need the join rows should use these.
  def denormalized_ingredient_ids
    read_attribute(:ingredient_ids)
  end

  def denormalized_tag_ids
    read_attribute(:tag_ids)
  end

  # Bulk writers attach many joins to the same item, and every join rewrites
  # the whole array. Inside this block the touched items are collected and
  # each array is rebuilt once, before the block's transaction commits.
  def self.defer_denormalization(&block)
    SyncsDenormalizedIds.defer(&block)
  end
end
