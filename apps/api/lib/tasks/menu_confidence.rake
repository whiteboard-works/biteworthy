# frozen_string_literal: true

namespace :biteworthy do
  namespace :menus do
    desc "Backfill confidence for a restaurant's published items from accepted ingestion items"
    task :backfill_confidence, [ :restaurant_uuid ] => :environment do |_t, args|
      restaurant_uuid = args[:restaurant_uuid]
      dry_run = ENV.fetch("DRY_RUN", "true") == "true"

      unless restaurant_uuid
        puts "ERROR: restaurant_uuid required"
        puts "Usage: bin/rails biteworthy:menus:backfill_confidence[<uuid>] [DRY_RUN=false]"
        puts "Example: bin/rails biteworthy:menus:backfill_confidence[123e4567-e89b-12d3-a456-426614174000] DRY_RUN=false"
        exit 1
      end

      restaurant = Restaurant.find_by(id: restaurant_uuid)
      unless restaurant
        puts "ERROR: Restaurant #{restaurant_uuid} not found"
        exit 1
      end

      puts "== Backfilling confidence for #{restaurant.name} =="
      puts "   Mode: #{dry_run ? 'DRY RUN (no changes will be made)' : 'LIVE (changes will be applied)'}"
      puts ""

      result = Admin::BackfillConfidence.call(restaurant: restaurant, dry_run: dry_run)

      if result[:items].any?
        puts "Processed #{result[:items_processed]} items with changes:"
        puts ""

        result[:items].each do |item|
          puts "  #{item[:item_name]} (#{item[:item_id]})"
          puts "    Confidence: #{item[:old_confidence]} → #{item[:new_confidence]}"

          if item[:changes].any?
            puts "    Changes:"
            item[:changes].each do |change|
              case change[:type]
              when :updated
                puts "      • Updated #{change[:model].demodulize} #{change[:slug]}: " \
                     "#{change[:old_source]}/#{change[:old_confidence]} → " \
                     "#{change[:new_source]}/#{change[:new_confidence]}"
              when :added
                puts "      • Added #{change[:model].demodulize} #{change[:slug]}: " \
                     "#{change[:source]}/#{change[:confidence]}"
              end
            end
          end

          if item[:allergen_rows_added].any?
            puts "    ⚠️  Allergen rows added: #{item[:allergen_rows_added].join(', ')}"
          end

          puts ""
        end
      else
        puts "No items needed backfilling."
      end

      if dry_run
        puts ""
        puts "== DRY RUN COMPLETE =="
        puts "To apply these changes, run with DRY_RUN=false:"
        puts "  bin/rails biteworthy:menus:backfill_confidence[#{restaurant_uuid}] DRY_RUN=false"
      else
        puts "== BACKFILL COMPLETE =="
      end
    end

    desc "Re-extract a restaurant's menu from its latest inputs (creates new STAGED scan)"
    task :reextract_restaurant, [ :restaurant_uuid ] => :environment do |_t, args|
      restaurant_uuid = args[:restaurant_uuid]
      dry_run = ENV.fetch("DRY_RUN", "true") == "true"

      unless restaurant_uuid
        puts "ERROR: restaurant_uuid required"
        puts "Usage: bin/rails biteworthy:menus:reextract_restaurant[<uuid>] [DRY_RUN=false]"
        puts "Example: bin/rails biteworthy:menus:reextract_restaurant[123e4567-e89b-12d3-a456-426614174000]"
        exit 1
      end

      restaurant = Restaurant.find_by(id: restaurant_uuid)
      unless restaurant
        puts "ERROR: Restaurant #{restaurant_uuid} not found"
        exit 1
      end

      latest_run = restaurant.ingestion_runs.order(created_at: :desc).first
      unless latest_run
        puts "ERROR: No ingestion runs found for #{restaurant.name}"
        exit 1
      end

      puts "== Re-extracting #{restaurant.name} =="
      puts "   Latest run: #{latest_run.id} (#{latest_run.status})"
      puts "   Mode: #{dry_run ? 'DRY RUN' : 'LIVE'}"
      puts ""

      # Check for attached inputs
      unless latest_run.inputs.attached?
        puts "ERROR: No inputs attached to run #{latest_run.id}"
        puts "The inputs attachment is required to re-extract."
        exit 1
      end

      input_count = latest_run.inputs.blobs.count
      puts "Found #{input_count} input(s) to re-extract"

      if dry_run
        puts ""
        puts "== DRY RUN COMPLETE =="
        puts "Would create a new STAGED ingestion run from #{input_count} input(s)."
        puts "To proceed, run with DRY_RUN=false:"
        puts "  bin/rails biteworthy:menus:reextract_restaurant[#{restaurant_uuid}] DRY_RUN=false"
        exit 0
      end

      # Get the user who created the original run
      user = User.find_by(id: latest_run.user_id)
      unless user
        puts "ERROR: User #{latest_run.user_id} not found (needed to create new run)"
        exit 1
      end

      # Determine input_kind from the first blob
      first_blob = latest_run.inputs.blobs.first
      input_kind = case first_blob.content_type
      when /image/ then "photo"
      when /pdf/ then "pdf"
      else "photo" # default
      end

      # Create new staged run
      new_run = restaurant.ingestion_runs.create!(
        status: "queued",
        input_kind: input_kind,
        user: user
      )

      # Attach the same inputs
      latest_run.inputs.blobs.each do |blob|
        new_run.inputs.attach(blob)
      end

      # Start the ingestion
      files = latest_run.inputs.blobs.map do |blob|
        {
          io: StringIO.new(blob.download),
          filename: blob.filename.to_s,
          content_type: blob.content_type
        }
      end

      Ingestion::StartRun.call(user: user, restaurant: restaurant, files: files)

      puts "Started new extraction: run #{new_run.id}"
      puts "Status: #{new_run.reload.status}"
      puts ""
      puts "== DONE =="
    end
  end
end
