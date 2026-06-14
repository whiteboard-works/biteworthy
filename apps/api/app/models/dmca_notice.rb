class DmcaNotice < ApplicationRecord
  # Legal remediation E10 — a copyright takedown notice filed at /dmca.
  #
  # The §512(c)(3) notice requires, among other things, a good-faith
  # statement and a statement (under penalty of perjury) that the
  # notice is accurate — both captured as required checkboxes. We store
  # every notice so there's an auditable trail and the data behind the
  # repeat-infringer process (an admin review over these rows, plus L2:
  # registering the designated agent).
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  STATUSES = %w[received actioned rejected].freeze

  validates :complainant_name,  presence: true
  validates :complainant_email, presence: true, format: { with: EMAIL_REGEX }
  validates :infringing_url,    presence: true
  validates :work_description,  presence: true
  validates :signature,         presence: true
  validates :status, inclusion: { in: STATUSES }
  # Both §512(c)(3) sworn statements must be affirmed for a valid notice.
  validate :statements_affirmed

  before_validation :normalize_email

  private

  def normalize_email
    self.complainant_email = complainant_email.to_s.strip.downcase if complainant_email.present?
  end

  def statements_affirmed
    errors.add(:good_faith, "must be affirmed") unless good_faith
    errors.add(:accuracy_sworn, "must be affirmed") unless accuracy_sworn
  end
end
