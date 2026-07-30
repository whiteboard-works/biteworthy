# frozen_string_literal: true

# Manages the `users.is_admin` roster from a trusted context (rake /
# console). Kept as a service so the admin:grant / admin:revoke /
# admin:sync tasks stay thin and the logic is spec-testable — same
# split as Biteworthy::EmailSmoke / ProductionSmoke.
#
# Deliberately does NOT create placeholder users for unknown emails:
# User.from_omniauth looks up by (provider, uid), not email, so a
# pre-created stub would collide with a later OAuth signup on the
# users.email unique index. Unknown emails are reported and skipped;
# re-run after the account signs up.
module Biteworthy
  class AdminRoster
    def initialize(logger: $stdout)
      @logger = logger
    end

    # Returns :granted, :already_admin, or :missing.
    def grant(email)
      with_user(email) do |user|
        return :already_admin if user.is_admin?

        user.update!(is_admin: true)
        log "granted admin → #{user.email} (#{user.id})"
        :granted
      end
    end

    # Returns :revoked, :not_admin, or :missing.
    def revoke(email)
      with_user(email) do |user|
        return :not_admin unless user.is_admin?

        user.update!(is_admin: false)
        log "revoked admin → #{user.email} (#{user.id})"
        :revoked
      end
    end

    # Grants every address in `emails` (typically ENV["ADMIN_EMAILS"],
    # comma-separated). Idempotent; returns { email => result }.
    def sync(emails)
      emails.to_s.split(",").map(&:strip).reject(&:empty?).index_with do |email|
        grant(email)
      end
    end

    private

    def with_user(email)
      # Devise downcases emails on write; normalize before lookup.
      user = User.find_by(email: email.to_s.strip.downcase)
      unless user
        log "no account for #{email} — run again after signup"
        return :missing
      end

      yield user
    end

    def log(message)
      @logger << "AdminRoster: #{message}\n"
    end
  end
end
