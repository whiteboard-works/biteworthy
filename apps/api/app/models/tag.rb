class Tag < ApplicationRecord
  FAMILIES = %w[diet allergen cuisine prep flavor].freeze

  has_many :item_tags, dependent: :destroy
  has_many :items, through: :item_tags

  validates :slug, :name, :path, :family, presence: true
  validates :slug, uniqueness: true
  validates :family, inclusion: { in: FAMILIES }

  scope :descendants_of, ->(path) { where("path <@ ?", path) }
end
