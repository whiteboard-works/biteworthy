# frozen_string_literal: true

# Phase 5.3 — migrates ActiveStorage blobs whose `service_name` doesn't
# match the env's currently-configured service. Idempotent: blobs
# already on the right service are no-ops.
#
# When does this matter?
#
#   * After flipping `production.rb` from `:amazon` (or `:local`) to
#     `:r2`, older blobs still record `service_name = "amazon"` (or
#     "local"). Their downloads keep working from the old service AS
#     LONG AS the credentials are still set, but new uploads go to
#     R2 — leaving a bifurcated set the next operator has to remember.
#     This task copies them across so production has one source of
#     truth.
#
#   * When dev/test runs accidentally seed local-disk attachments
#     into a production database (rare but happens with shared DB
#     dumps). Re-running with R2 creds set migrates them.
#
# Returns true if every blob ends up on the target service. Logs each
# migration as `[ok]  <id>  <old_service> → <new_service>` and any
# failure as `[FAIL] <id>  <error>`. Skipped (already-on-target) blobs
# log `[skip] <id>  already on <service>` to keep the audit trail
# explicit.
#
# Wraps `ActiveStorage::Blob#open` (download) + `Blob.service.upload`
# (upload-to-target) + `Blob#update_columns` (rewrite service_name).
# Doesn't delete the source blob — humans confirm the migration
# before flipping the old service's bucket lifecycle to expire keys.
module Biteworthy
  class StorageBackfill
    Result = Struct.new(:migrated, :skipped, :failed, keyword_init: true)

    def initialize(target_service: ActiveStorage::Blob.service.name, logger: $stdout)
      @target_service = target_service.to_s
      @logger         = logger
    end

    def run
      result = Result.new(migrated: 0, skipped: 0, failed: 0)
      @logger.puts "BiteWorthy storage backfill → #{@target_service}"

      ActiveStorage::Blob.find_each do |blob|
        case status_for(blob)
        when :on_target
          @logger.puts "  [skip] #{blob.id}  already on #{blob.service_name}"
          result.skipped += 1
        when :needs_migration
          # Capture the source service name BEFORE migrate rewrites it
          # via update_columns (which bypasses dirty tracking).
          from_service = blob.service_name
          migrated, error = migrate(blob)
          if migrated
            @logger.puts "  [ok]   #{blob.id}  #{from_service} → #{@target_service}"
            result.migrated += 1
          else
            @logger.puts "  [FAIL] #{blob.id}  #{error}"
            result.failed += 1
          end
        end
      end

      @logger.puts(
        "  → migrated=#{result.migrated}  skipped=#{result.skipped}  failed=#{result.failed}"
      )
      result
    end

    private

    def status_for(blob)
      blob.service_name.to_s == @target_service ? :on_target : :needs_migration
    end

    # Download via the source service, upload to the target, rewrite
    # service_name. ActiveStorage::Service.lookup builds clients
    # lazily from storage.yml so naming the source service by string
    # is enough.
    def migrate(blob)
      source = ActiveStorage::Blob.services.fetch(blob.service_name)
      target = ActiveStorage::Blob.services.fetch(@target_service)

      source.open(blob.key, checksum: blob.checksum) do |file|
        target.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type)
      end

      blob.update_columns(service_name: @target_service)
      [true, nil]
    rescue StandardError => e
      [false, "#{e.class}: #{e.message}"]
    end
  end
end
