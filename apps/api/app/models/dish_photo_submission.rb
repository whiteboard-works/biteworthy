# frozen_string_literal: true

# A diner-submitted photo of a dish, waiting on a moderator before it
# can become Item#photo. The filter never reads this table — only the
# approved copy on the item is public. Pending rows are the queue.
class DishPhotoSubmission < ApplicationRecord
  include HasPhotoValidation

  STATUSES = %w[pending approved rejected].freeze
  REJECTION_REASONS = %w[not_this_dish low_quality inappropriate not_food duplicate].freeze
  DAILY_LIMIT_PER_USER = 10
  PENDING_PER_ITEM_LIMIT = 3

  belongs_to :item
  belongs_to :user, optional: true
  belongs_to :review, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :credited_items, class_name: "Item", foreign_key: :photo_submission_id,
           dependent: :nullify, inverse_of: :photo_submission

  has_one_attached :photo

  validates :status, inclusion: { in: STATUSES }
  validates :rejection_reason, inclusion: { in: REJECTION_REASONS }, allow_nil: true
  validates :owns_rights, inclusion: { in: [ true ], message: "must be accepted — you have to confirm you took this photo" }
  validates :credit_name, presence: true
  validate :photo_is_attached
  validate :rejection_reason_matches_status
  validate :review_belongs_to_same_item_and_user

  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :newest_first, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  private

  def photo_is_attached
    errors.add(:photo, "must be attached") unless photo.attached?
  end

  def rejection_reason_matches_status
    if status == "rejected" && rejection_reason.blank?
      errors.add(:rejection_reason, "is required when rejecting")
    elsif status != "rejected" && rejection_reason.present?
      errors.add(:rejection_reason, "must be blank unless the submission is rejected")
    end
  end

  def review_belongs_to_same_item_and_user
    return if review.nil?

    errors.add(:review, "must be of the same dish") if review.item_id != item_id
    errors.add(:review, "must belong to the same diner") if user_id.present? && review.user_id != user_id
  end
end
