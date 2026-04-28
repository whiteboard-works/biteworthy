class MenuGroup < ActiveRecord::Base
   belongs_to :restaurant
  #  has_and_belongs_to_many :items, dependent: :destroy
   has_and_belongs_to_many :tags

   has_and_belongs_to_many :items
   has_and_belongs_to_many :menus

   validates :name, :restaurant_id, presence: true

end
