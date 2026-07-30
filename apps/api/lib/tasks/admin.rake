# frozen_string_literal: true

# Admin-roster management. All three tasks are idempotent and safe to
# re-run; unknown emails are reported and skipped (see
# Biteworthy::AdminRoster for why they are never pre-created).
#
# Usage:
#   bin/rails "admin:grant[skylar@example.com]"
#   bin/rails "admin:revoke[skylar@example.com]"
#   ADMIN_EMAILS=a@x.com,b@y.com bin/rails admin:sync
namespace :admin do
  desc "Grant is_admin to the user with the given email"
  task :grant, [:email] => :environment do |_t, args|
    abort("usage: admin:grant[email]") if args[:email].blank?
    Biteworthy::AdminRoster.new.grant(args[:email])
  end

  desc "Revoke is_admin from the user with the given email"
  task :revoke, [:email] => :environment do |_t, args|
    abort("usage: admin:revoke[email]") if args[:email].blank?
    Biteworthy::AdminRoster.new.revoke(args[:email])
  end

  desc "Grant is_admin to every email in ADMIN_EMAILS (comma-separated)"
  task sync: :environment do
    abort("ADMIN_EMAILS must be set") if ENV["ADMIN_EMAILS"].blank?
    Biteworthy::AdminRoster.new.sync(ENV["ADMIN_EMAILS"])
  end
end
