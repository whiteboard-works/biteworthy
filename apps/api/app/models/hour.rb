class Hour < ApplicationRecord
  belongs_to :restaurant
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }

  # Sort by day of week, then opening time for multiple shifts per day
  default_scope -> { order(:day_of_week, :opens_at) }
end
