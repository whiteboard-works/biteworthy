class DietaryProfileIngredient < ApplicationRecord
  belongs_to :dietary_profile
  belongs_to :ingredient
end
