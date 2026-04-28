class ItemsIngredient < ActiveRecord::Base
  include TrackPoints

  belongs_to :item
  belongs_to :ingredient

  validates_uniqueness_of :item_id, scope: :ingredient_id
end
