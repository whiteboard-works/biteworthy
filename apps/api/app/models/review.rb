class Review < ApplicationRecord
  # Phase 4.3 — adds the optional photo + content/size validation. The
  # rating + body columns shipped in Phase 0; this only changes the
  # behavior, no migration.
  MAX_PHOTO_BYTES = 5 * 1024 * 1024 # 5 MB
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/jpg image/png image/heic image/heif image/webp].freeze

  # Phase 4.6 — moderation reasons. Stored as a string column rather
  # than a Postgres enum so we can add new reasons without a data
  # migration.
  HIDDEN_REASONS = %w[spam abuse duplicate off_topic].freeze

  # Lightweight spam heuristic (Phase 4.6). The list is intentionally
  # short — a moderator clears the queue, the queue stays small, the
  # heuristic doesn't have to be smart. ML lives in a future phase.
  PROFANITY_WORDS = %w[
    fuck shit bitch cunt nigger faggot chink kike spic
  ].freeze
  URL_PATTERN = %r{(?:https?://|www\.)\S+}i

  belongs_to :user
  belongs_to :item

  has_one_attached :photo

  validates :rating,        presence: true, inclusion: { in: 1..5 }
  validates :hidden_reason, inclusion: { in: HIDDEN_REASONS }, allow_nil: true
  validate  :photo_within_size_limit
  validate  :photo_is_an_allowed_image_type

  scope :newest_first,        -> { order(created_at: :desc) }
  scope :visible,             -> { where(hidden_at: nil) }
  scope :hidden,              -> { where.not(hidden_at: nil) }
  scope :awaiting_moderation, -> { where(hidden_at: nil).where.not(flagged_at: nil) }

  before_save :auto_flag_if_suspicious

  def hidden?
    hidden_at.present?
  end

  def flagged?
    flagged_at.present?
  end

  # Mark a review as hidden with a recorded reason. Idempotent — if
  # the review is already hidden, just refreshes the timestamp +
  # reason so the audit trail reflects the most recent decision.
  def hide!(reason:)
    raise ArgumentError, "unknown hidden_reason: #{reason}" unless HIDDEN_REASONS.include?(reason.to_s)
    update!(hidden_at: Time.current, hidden_reason: reason.to_s, flagged_at: nil)
  end

  # Restore a previously hidden review. Clears the queue flag too —
  # if it tripped the heuristic before, a moderator already decided
  # it's fine.
  def unhide!
    update!(hidden_at: nil, hidden_reason: nil, flagged_at: nil)
  end

  # Whether the body looks like spam under the lightweight heuristic.
  # Public so specs + the Avo "rerun heuristic" action can call it.
  def suspicious?
    text = body.to_s
    return false if text.strip.empty?
    return true if URL_PATTERN.match?(text)
    lowered = text.downcase
    PROFANITY_WORDS.any? { |word| lowered.match?(/\b#{Regexp.escape(word)}\b/) }
  end

  private

  def photo_within_size_limit
    return unless photo.attached?
    return if photo.byte_size <= MAX_PHOTO_BYTES
    errors.add(:photo, "must be #{MAX_PHOTO_BYTES / 1.megabyte} MB or smaller")
  end

  def photo_is_an_allowed_image_type
    return unless photo.attached?
    return if ALLOWED_PHOTO_TYPES.include?(photo.content_type)
    errors.add(:photo, "must be one of #{ALLOWED_PHOTO_TYPES.join(', ')}")
  end

  # Phase 4.6 — pre-save callback that drops a flag for moderation
  # when the body trips the heuristic. Doesn't hide the review (only
  # a moderator does that) — just surfaces it in the queue.
  def auto_flag_if_suspicious
    return unless body_changed? || new_record?
    if suspicious?
      self.flagged_at ||= Time.current
    end
  end
end
