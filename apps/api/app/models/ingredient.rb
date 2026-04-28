class Ingredient < ApplicationRecord
  has_many :item_ingredients, dependent: :destroy
  has_many :items, through: :item_ingredients

  validates :slug, :name, :path, presence: true
  validates :slug, uniqueness: true

  # ltree-powered descendant lookup: every node that lives under this one.
  scope :descendants_of, ->(path) { where("path <@ ?", path) }
  scope :ancestors_of,   ->(path) { where("path @> ?", path) }
end
