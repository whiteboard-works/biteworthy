class WaitlistSignup < ApplicationRecord
  # Phase 5.10 — soft-launch waitlist signups.
  #
  # Email validation is intentionally lenient: a regex that catches
  # the obvious typos (no `@`, no `.`, whitespace) but doesn't try
  # to enforce RFC 5322. Postmark's bounce handling is the real
  # filter. The citext column ensures dupes match case-insensitively.
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  SOURCES = %w[landing press footer mobile_app].freeze

  validates :email, presence: true, format: { with: EMAIL_REGEX }
  validates :source, inclusion: { in: SOURCES }

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end
end
