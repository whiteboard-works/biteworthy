class MenuSection < ApplicationRecord
  belongs_to :menu
  has_many :items, dependent: :nullify
end
