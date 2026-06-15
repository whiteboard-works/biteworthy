class DietaryProfile < ApplicationRecord
  has_many :dietary_profile_ingredients, dependent: :destroy
  has_many :dietary_profile_tags,        dependent: :destroy
  has_many :ingredients, through: :dietary_profile_ingredients
  has_many :tags,        through: :dietary_profile_tags

  validates :slug, :name, presence: true
  validates :slug, uniqueness: true

  # The preset's "avoid" rule rows, as plain id arrays — the shape the
  # filter (items endpoint, cities ranking) and the preset serializers
  # consume. Kept here so the `rule: "avoid"` query lives in one place.
  def avoid_ingredient_ids
    dietary_profile_ingredients.where(rule: "avoid").pluck(:ingredient_id)
  end

  def avoid_tag_ids
    dietary_profile_tags.where(rule: "avoid").pluck(:tag_id)
  end
end
