# frozen_string_literal: true

namespace :biteworthy do
  namespace :photos do
    desc "Collapse duplicate Item#photo attachments to the credited (or newest) blob. DRY_RUN=true by default."
    task collapse_duplicate_photos: :environment do
      dry_run = ENV.fetch("DRY_RUN", "true") == "true"
      result = DishPhotos::CollapseDuplicatePhotos.call(dry_run: dry_run)

      warn "== Collapsing duplicate dish photos =="
      warn "   Mode: #{dry_run ? "DRY RUN" : "LIVE"}"
      warn "   Items with extras: #{result[:items_examined]}"
      warn "   Attachments to drop: #{result[:attachments_purged]}"
      result[:details].each do |row|
        warn "  item #{row[:item_id]} keep #{row[:kept_blob_id]} purge #{row[:purged_blob_ids].join(", ")}"
      end

      if dry_run
        warn "To apply: DRY_RUN=false bin/rails biteworthy:photos:collapse_duplicate_photos"
      end
    end
  end
end
