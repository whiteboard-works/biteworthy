class ItemsMenuGroups < ActiveRecord::Base
  include TrackPoints

  belongs_to :menu_group
  belongs_to :item

  validates_uniqueness_of :menu_group_id, scope: :item_id
end
