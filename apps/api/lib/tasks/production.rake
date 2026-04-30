# frozen_string_literal: true

# Phase 5.1 — production smoke task.
#
# Wraps Biteworthy::ProductionSmoke (app/services/biteworthy/) with
# a Rake-friendly entrypoint. The runner stays read-only so this task
# is safe to call from CI on every deploy.
#
# Usage:
#   bin/rails biteworthy:production:smoke              # uses PUBLIC_HOST
#   bin/rails biteworthy:production:smoke HOST=...     # override target
#   bin/rails biteworthy:production:smoke EXIT_CODE=1  # exit non-zero on
#                                                      # any failure (CI mode)
namespace :biteworthy do
  namespace :production do
    desc "Smoke-test the deployed API on /up + a real items query"
    task :smoke => :environment do
      host = ENV["HOST"].presence ||
             ENV["PUBLIC_HOST"].presence ||
             abort("HOST or PUBLIC_HOST must be set")

      runner = Biteworthy::ProductionSmoke.new(host: host, logger: $stdout)
      ok = runner.run

      exit(1) if ENV["EXIT_CODE"] == "1" && !ok
    end
  end
end
