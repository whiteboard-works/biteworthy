class ItemsExtra < ActiveRecord::Base
  include TrackPoints

  belongs_to :extra
  belongs_to :item

  validates_uniqueness_of :item_id, scope: :extra_id
end
