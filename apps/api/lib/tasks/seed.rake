# frozen_string_literal: true

# Phase 5.7 — Durango batch ingest task.
#
# Wraps Biteworthy::DurangoSeed with a Rake adapter. CSV path is
# required; everything else has sensible defaults.
#
# Usage:
#   bin/rails biteworthy:seed:durango FILE=docs/seeds/durango.csv
#   bin/rails biteworthy:seed:durango FILE=... WAIT=0   # skip polling
#   bin/rails biteworthy:seed:durango FILE=... CITY=durango CITY_REGION=CO
#   bin/rails biteworthy:seed:durango FILE=... EXIT_CODE=1  # CI mode
namespace :biteworthy do
  namespace :seed do
    desc "Batch ingest Durango restaurants from a CSV"
    task :durango => :environment do
      file = ENV["FILE"].presence || abort("FILE=<path/to/durango.csv> is required")
      abort("FILE not found: #{file}") unless File.exist?(file)

      runner = Biteworthy::DurangoSeed.new(
        csv_path:     file,
        city_slug:    ENV.fetch("CITY", "durango"),
        city_name:    ENV.fetch("CITY_NAME", "Durango"),
        city_region:  ENV.fetch("CITY_REGION", "CO"),
        wait_seconds: (ENV["WAIT"].presence || "600").to_i,
        logger:       $stdout
      )
      result = runner.run

      exit(1) if ENV["EXIT_CODE"] == "1" && result.failed.positive?
    end
  end
end
