# frozen_string_literal: true

# Phase 5.3 — ActiveStorage backfill task.
#
# Wraps Biteworthy::StorageBackfill with a Rake adapter. Idempotent:
# safe to run from a `fly ssh console` after the R2 secrets are set,
# and safe to re-run any time the production service flips.
#
# Usage:
#   bin/rails biteworthy:storage:backfill
#   bin/rails biteworthy:storage:backfill TARGET=amazon  # override target
#   bin/rails biteworthy:storage:backfill EXIT_CODE=1    # CI mode
namespace :biteworthy do
  namespace :storage do
    desc "Migrate ActiveStorage blobs to the configured (or TARGET=) service"
    task :backfill => :environment do
      target = ENV["TARGET"].presence || ActiveStorage::Blob.service.name

      runner = Biteworthy::StorageBackfill.new(target_service: target, logger: $stdout)
      result = runner.run

      exit(1) if ENV["EXIT_CODE"] == "1" && result.failed.positive?
    end
  end
end
