# frozen_string_literal: true

# Admin-roster management. Every task is idempotent and safe to re-run;
# unknown emails are reported and skipped (see Biteworthy::AdminRoster
# for why they are never pre-created).
#
# Usage:
#   bin/rails "admin:grant[skylar@example.com]"
#   bin/rails "admin:revoke[skylar@example.com]"
#   ADMIN_EMAILS=a@x.com,b@y.com bin/rails admin:sync
#
#   bin/rails "admin:grant_super[skylar@example.com]"
#   bin/rails "admin:revoke_super[skylar@example.com]"
#   SUPER_ADMIN_EMAILS=a@x.com,b@y.com bin/rails admin:sync_super
#
# The super tier lifts the spend ceilings, the tool-round cap, the
# ingestion input caps, and the request throttle. It is deliberately
# unreachable over HTTP — shell access is the grant mechanism.
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

  desc "Grant is_admin to every email in ADMIN_EMAILS (comma-separated; never revokes)"
  task sync: :environment do
    abort("ADMIN_EMAILS must be set") if ENV["ADMIN_EMAILS"].blank?
    Biteworthy::AdminRoster.new.sync(ENV["ADMIN_EMAILS"])
  end

  # Opt out of the confirmation-gate bypass with SKIP_CONFIRMATIONS=false
  # (or 0 / no / off) — the destructive-tool gate is what parks an
  # avoid-list removal for a human answer, and a super admin who wants to
  # keep it should not have to edit the column by hand.
  #
  # A lambda rather than a `def`: `namespace` yields its block instead of
  # instance_eval'ing it, and a block does not change the default definee,
  # so a `def` here would land on `Object` and give every object in the
  # rake process an ENV-reading `skip_confirmations?`.
  #
  # `Boolean.cast` rather than `!= "false"`: the string comparison treats
  # only exact lowercase "false" as opt-out, so `SKIP_CONFIRMATIONS=0`
  # would silently turn the gate *off* — the opposite of the ask, on the
  # one setting where being wrong means an allergen can be removed
  # without anyone being asked.
  skip_confirmations = lambda do
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SKIP_CONFIRMATIONS", "true")) != false
  end

  desc "Grant is_super_admin (implies is_admin) to the user with the given email"
  task :grant_super, [:email] => :environment do |_t, args|
    abort("usage: admin:grant_super[email]") if args[:email].blank?
    Biteworthy::AdminRoster.new.grant_super(args[:email], skip_confirmations: skip_confirmations.call)
  end

  desc "Revoke is_super_admin (leaves is_admin) from the user with the given email"
  task :revoke_super, [:email] => :environment do |_t, args|
    abort("usage: admin:revoke_super[email]") if args[:email].blank?
    Biteworthy::AdminRoster.new.revoke_super(args[:email])
  end

  desc "Grant is_super_admin to every email in SUPER_ADMIN_EMAILS (comma-separated; never revokes)"
  task sync_super: :environment do
    abort("SUPER_ADMIN_EMAILS must be set") if ENV["SUPER_ADMIN_EMAILS"].blank?
    Biteworthy::AdminRoster.new.sync_super(ENV["SUPER_ADMIN_EMAILS"],
                                           skip_confirmations: skip_confirmations.call)
  end
end
