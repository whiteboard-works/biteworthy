class FoodsVariety < ActiveRecord::Base
  include TrackPoints

  belongs_to :food
  belongs_to :variety

  validates_uniqueness_of :food_id, scope: :variety_id

end
