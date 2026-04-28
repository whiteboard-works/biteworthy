class ItemsTag < ActiveRecord::Base
  include TrackPoints

  belongs_to :tag
  belongs_to :item

  validates_uniqueness_of :item_id, scope: :tag_id

end
