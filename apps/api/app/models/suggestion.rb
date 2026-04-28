class Suggestion < ApplicationRecord
  STATUSES = %w[pending accepted rejected].freeze

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true
  belongs_to :resolved_by_user, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :kind, presence: true
end
