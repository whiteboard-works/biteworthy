class UserProfile < ApplicationRecord
  STRICTNESS = %w[relaxed balanced strict].freeze

  belongs_to :user
  belongs_to :primary_dietary_profile, class_name: "DietaryProfile", optional: true

  validates :strictness, inclusion: { in: STRICTNESS }
end
