class RestaurantVisit < ApplicationRecord
  # Phase 4.8 — "My filtered menus" history.
  # One row per (user, restaurant, day). RecordRestaurantVisitJob
  # upserts; the controller never touches this table directly.

  belongs_to :user
  belongs_to :restaurant

  validates :viewed_on, presence: true
  validates :user_id, uniqueness: { scope: [:restaurant_id, :viewed_on] }

  scope :newest_first, -> { order(updated_at: :desc) }
end
