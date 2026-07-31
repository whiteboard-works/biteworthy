class MenuSection < ApplicationRecord
  belongs_to :menu
  has_many :items, dependent: :nullify

  # The column is NOT NULL with no default — without this a
  # nameless create would surface as a 500 instead of a 422.
  validates :name, presence: true
end
