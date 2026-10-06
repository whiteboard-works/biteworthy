# frozen_string_literal: true

namespace :biteworthy do
  namespace :menus do
    desc "Backfill confidence for a restaurant's published items from accepted ingestion items"
    task :backfill_confidence, [ :restaurant_uuid ] => :environment do |_t, args|
      restaurant_uuid = args[:restaurant_uuid]
      dry_run = ENV.fetch("DRY_RUN", "true") == "true"

      unless restaurant_uuid
        warn "ERROR: restaurant_uuid required"
        warn "Usage: bin/rails biteworthy:menus:backfill_confidence[<uuid>] [DRY_RUN=false]"
        exit 1
      end

      restaurant = Restaurant.find_by(id: restaurant_uuid)
      unless restaurant
        warn "ERROR: Restaurant #{restaurant_uuid} not found"
        exit 1
      end

      warn "== Backfilling confidence for #{restaurant.name} =="
      warn "   Mode: #{dry_run ? 'DRY RUN' : 'LIVE'}"

      result = Admin::BackfillConfidence.call(restaurant: restaurant, dry_run: dry_run)

      if result[:items].empty?
        warn "No items needed backfilling."
      else
        warn "Processed #{result[:items_processed]} items with changes:"
        result[:items].each do |item|
          warn "  #{item[:item_name]} (#{item[:item_id]})"
          warn "    Confidence: #{item[:old_confidence]} → #{item[:new_confidence]}"
          warn "    Rows changed: #{item[:rows_changed]}"
          warn "    Allergen rows added: #{item[:allergen_rows_added].join(', ')}" if item[:allergen_rows_added].any?
        end
      end

      if dry_run
        warn "To apply: bin/rails biteworthy:menus:backfill_confidence[#{restaurant_uuid}] DRY_RUN=false"
      end
    end
  end
end
