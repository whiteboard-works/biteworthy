class ItemsFood < ActiveRecord::Base
  include TrackPoints

  belongs_to :food
  belongs_to :item

  validates_uniqueness_of :item_id, scope: :food_id
end
