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
        if user.is_admin?
          log "already admin — #{user.email}"
          return :already_admin
        end

        user.update!(is_admin: true)
        log "granted admin → #{user.email} (#{user.id})"
        :granted
      end
    end

    # Returns :revoked, :not_admin, or :missing. Also clears the super
    # bit: the CHECK constraint forbids a super admin who is not an
    # admin, and leaving it set would make the revoke fail rather than
    # partially apply.
    def revoke(email)
      with_user(email) do |user|
        unless user.is_admin?
          log "not an admin — #{user.email}"
          return :not_admin
        end

        user.update!(is_admin: false, is_super_admin: false, skip_confirmations: false)
        log "revoked admin → #{user.email} (#{user.id})"
        :revoked
      end
    end

    # The tier above admin — no spend ceilings, no round cap, no request
    # throttle. Reachable only from here (rake / console), which is the
    # design: any admin can promote another admin over HTTP, so if that
    # promotion also lifted the spend ceilings, one of them would hand out
    # an uncapped bill. Grants `is_admin` alongside, because the CHECK
    # constraint requires it and every existing gate reads that column.
    #
    # Returns :granted, :already_super_admin, or :missing.
    def grant_super(email, skip_confirmations: true)
      with_user(email) do |user|
        if user.is_super_admin? && user.skip_confirmations == skip_confirmations
          log "already super admin — #{user.email}"
          return :already_super_admin
        end

        user.update!(is_admin: true, is_super_admin: true, skip_confirmations: skip_confirmations)
        log "granted super admin → #{user.email} (#{user.id}) " \
            "(confirmations #{skip_confirmations ? 'skipped' : 'enforced'})"
        :granted
      end
    end

    # Returns :revoked, :not_super_admin, or :missing. Leaves `is_admin`
    # alone — dropping to plain admin is the useful demotion here.
    def revoke_super(email)
      with_user(email) do |user|
        unless user.is_super_admin?
          log "not a super admin — #{user.email}"
          return :not_super_admin
        end

        user.update!(is_super_admin: false, skip_confirmations: false)
        log "revoked super admin → #{user.email} (#{user.id})"
        :revoked
      end
    end

    # Grants every address in `emails` (typically ENV["ADMIN_EMAILS"],
    # comma-separated). Idempotent; returns { email => result }.
    def sync(emails)
      each_email(emails).index_with { |email| grant(email) }
    end

    # Same, for the super tier (ENV["SUPER_ADMIN_EMAILS"]). Never revokes,
    # matching `sync` — a typo in the env var should not silently demote
    # the only operator who can still fix it.
    def sync_super(emails, skip_confirmations: true)
      each_email(emails).index_with do |email|
        grant_super(email, skip_confirmations: skip_confirmations)
      end
    end

    private

    def each_email(emails)
      emails.to_s.split(",").map(&:strip).reject(&:empty?)
    end

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
