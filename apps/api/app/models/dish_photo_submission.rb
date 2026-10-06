# frozen_string_literal: true

# A diner-submitted photo of a dish, waiting on a moderator before it
# can become Item#photo. The filter never reads this table — only the
# approved copy on the item is public. Pending rows are the queue.
class DishPhotoSubmission < ApplicationRecord
  include HasPhotoValidation

  STATUSES = %w[pending approved rejected withdrawn approve_keep].freeze
  REJECTION_REASONS = %w[not_this_dish low_quality inappropriate not_food duplicate].freeze
  # Statuses that have no stored image (purged on the way in).
  PHOTOLESS = %w[rejected withdrawn].freeze
  DAILY_LIMIT_PER_USER = 10
  PENDING_PER_ITEM_LIMIT = 3
  ANONYMOUS_CREDIT = "a diner"

  belongs_to :item
  belongs_to :user, optional: true
  belongs_to :review, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :credited_items, class_name: "Item", foreign_key: :photo_submission_id,
           dependent: :nullify, inverse_of: :photo_submission

  has_one_attached :photo do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 400, 400 ], format: :webp
  end

  validates :status, inclusion: { in: STATUSES }
  validates :rejection_reason, inclusion: { in: REJECTION_REASONS }, allow_nil: true
  validates :owns_rights, inclusion: { in: [ true ], message: "must be accepted — you have to confirm you took this photo" }
  validates :credit_name, presence: true
  validate :photo_is_attached
  validate :rejection_reason_matches_status
  validate :review_belongs_to_same_item_and_user

  scope :pending,       -> { where(status: "pending") }
  scope :approved,      -> { where(status: "approved") }
  scope :approve_keep,  -> { where(status: "approve_keep") }
  scope :accepted,      -> { where(status: %w[approved approve_keep]) }
  scope :rejected,      -> { where(status: "rejected") }
  scope :withdrawn,     -> { where(status: "withdrawn") }
  scope :newest_first,  -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def approve_keep?
    status == "approve_keep"
  end

  def rejected?
    status == "rejected"
  end

  def withdrawn?
    status == "withdrawn"
  end

  def credited?
    Item.exists?(photo_submission_id: id)
  end

  # Soft-delete: the row stays so it still counts toward the daily
  # limit, but the bytes go away.
  def withdraw!
    raise ActiveRecord::RecordInvalid, self unless pending?

    transaction do
      update!(status: "withdrawn")
      photo.purge if photo.attached?
    end
  end

  private

  def photo_is_attached
    return if PHOTOLESS.include?(status)

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
