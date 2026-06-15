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

  has_one_attached :photo

  validates :name, presence: true
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE }

  scope :published, -> { where(status: "published") }
end
