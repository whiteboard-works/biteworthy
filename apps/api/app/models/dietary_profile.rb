class DietaryProfile < ApplicationRecord
  has_many :dietary_profile_ingredients, dependent: :destroy
  has_many :dietary_profile_tags,        dependent: :destroy
  has_many :ingredients, through: :dietary_profile_ingredients
  has_many :tags,        through: :dietary_profile_tags

  validates :slug, :name, presence: true
  validates :slug, uniqueness: true
end
