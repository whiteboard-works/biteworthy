class Hour < ApplicationRecord
  belongs_to :restaurant
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
end
