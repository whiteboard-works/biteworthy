# frozen_string_literal: true

# Phase 5.2 — production SMTP smoke task.
#
# Wraps Biteworthy::EmailSmoke with a Rake adapter. Stays read-only
# (only sends to the EMAIL= argument; never persists a record). Safe
# to run from CI or from a `fly ssh console` post-deploy.
#
# Usage:
#   bin/rails biteworthy:email:smoke EMAIL=skylar@example.com
#   bin/rails biteworthy:email:smoke EMAIL=... EXIT_CODE=1   # CI mode
namespace :biteworthy do
  namespace :email do
    desc "Send a one-off SMTP smoke message to confirm production wiring"
    task :smoke => :environment do
      to = ENV["EMAIL"].presence || abort("EMAIL=<recipient> is required")

      ok = Biteworthy::EmailSmoke.new(to: to, logger: $stdout).run

      exit(1) if ENV["EXIT_CODE"] == "1" && !ok
    end
  end
end
