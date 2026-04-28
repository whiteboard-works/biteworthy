class FoodsTag < ActiveRecord::Base
  include TrackPoints

  belongs_to :food
  belongs_to :tag

  validates_uniqueness_of :food_id, scope: :tag_id

end
