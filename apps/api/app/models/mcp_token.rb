# frozen_string_literal: true

# A least-privilege credential for an MCP client.
#
# Connecting Claude Code today means handing it the same JWT the web app
# uses, which carries everything the account can do — for an admin, that
# is the taxonomy, the moderation queue, and every user's role. This is
# the alternative: a credential that names what it may touch, can be
# listed, and can be revoked without ending every other session.
#
# **The secret is shown once and never stored.** Only its SHA-256 lives
# here, so a leaked database is not a leaked set of working credentials.
# That is also why there is no "show me the token again" — there is
# nothing to show.
class McpToken < ApplicationRecord
  # Long enough that guessing is not a strategy, prefixed so a leaked one
  # is recognizable in a log or a paste and can be traced to this system.
  PREFIX     = "bw_mcp_"
  BYTES      = 32
  MAX_ACTIVE = 20

  belongs_to :user

  validates :name, presence: true, length: { maximum: 60 }
  # A token has to name what it may touch. Saying nothing used to mean
  # everything (see `Tools::Scopes::ALL`), so the least deliberate way to
  # fill this form produced the most powerful credential. Full authority
  # is still available — it is spelled `*` — but it has to be asked for.
  validates :scopes, presence: true
  validate  :scopes_are_known

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Returns the record and the one-time secret together, because this is
  # the only moment the secret exists.
  #
  # `scopes` has no default: the caller states what it is granting, and
  # `create!` raises rather than minting a credential whose authority
  # nobody chose.
  def self.issue!(user:, name:, scopes:, expires_at: nil)
    secret = "#{PREFIX}#{SecureRandom.urlsafe_base64(BYTES)}"
    token  = create!(
      user: user, name: name, scopes: Array(scopes).map(&:to_s).uniq,
      expires_at: expires_at, token_digest: digest(secret)
    )
    [token, secret]
  end

  # Constant-time lookup is not available here — the digest is the index —
  # but the digest of an attacker-supplied string reveals nothing about a
  # stored one, so an index lookup is safe.
  def self.authenticate(secret)
    return nil if secret.blank? || !secret.start_with?(PREFIX)

    active.find_by(token_digest: digest(secret))
  end

  def self.digest(secret) = Digest::SHA256.hexdigest(secret)

  # Deliberately not `touch` on every call: a timestamp accurate to the
  # minute answers "is this still in use?", and writing a row on every
  # tool call would put a write in front of every read.
  def note_use!
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  def revoke! = update!(revoked_at: Time.current)
  def revoked? = revoked_at.present?

  private

  def scopes_are_known
    unknown = Array(scopes).reject { |scope| Tools::Scopes.valid?(scope) }
    return if unknown.empty?

    errors.add(:scopes, "unknown: #{unknown.join(', ')}")
  end
end
