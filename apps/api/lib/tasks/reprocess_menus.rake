# frozen_string_literal: true

namespace :biteworthy do
  namespace :menus do
    desc "Identify items that may need re-review for new wheat-based ingredients"
    task audit_celiac_safety: :environment do
      # This task addresses the safety fixes from 2026-10-05: new wheat-based
      # ingredients (hotcake, biscuit, English muffin, wheat gravy, batter,
      # breading, roux) were added to the taxonomy, and the deterministic
      # resolver now catches samosa, relleno, and gulab jamun via IMPLIED_BASE_KEYWORDS.
      #
      # This audit identifies published items whose names contain these keywords
      # but don't have wheat ingredients associated, suggesting they may need
      # manual review or re-extraction.

      wheat = Ingredient.find_by(slug: "grain-wheat")
      unless wheat
        puts "ERROR: grain-wheat ingredient not found. Run db:seed first."
        exit 1
      end

      # Keywords from the updated IMPLIED_BASE_KEYWORDS plus new taxonomy entries
      wheat_keywords = %w[
        hotcake pancake biscuit muffin gravy roux batter breading
        samosa relleno tempura
      ]

      puts "== Auditing published items for hidden wheat sources =="
      puts "   Keywords: #{wheat_keywords.join(', ')}"
      puts ""

      issues = []

      Item.published.includes(:restaurant, :ingredients).find_each do |item|
        # Check if item name/description contains wheat keywords but has no wheat ingredients
        text = "#{item.name} #{item.description}".downcase
        matched_keywords = wheat_keywords.select { |kw| text.include?(kw) }

        next if matched_keywords.empty?

        # Check if any of the item's ingredients are under grain.wheat
        has_wheat = item.ingredients.any? do |ing|
          ing.path.to_s.start_with?("grain.wheat")
        end

        unless has_wheat
          issues << {
            restaurant: item.restaurant.name,
            item: item.name,
            keywords: matched_keywords,
            url: "/admin/restaurants/#{item.restaurant.id}/items/#{item.id}"
          }
        end
      end

      if issues.any?
        puts "Found #{issues.count} items that may need wheat ingredients:"
        puts ""

        issues.each do |issue|
          puts "  #{issue[:restaurant]} — #{issue[:item]}"
          puts "    Matched: #{issue[:keywords].join(', ')}"
          puts "    Admin: #{issue[:url]}"
          puts ""
        end

        puts "== Recommendations =="
        puts "1. Review these items manually in the admin UI"
        puts "2. For new menus, re-extract will use the updated taxonomy"
        puts "3. For existing menus, either:"
        puts "   - Manually add missing wheat ingredients via admin"
        puts "   - Re-scan the restaurant's menu to get a fresh extraction"
      else
        puts "No issues found! All keyword-matched items have wheat ingredients."
      end

      puts ""
      puts "== Done =="
    end

    # The fix the audit above only reports. Dry run by default: it lists
    # every dish it would change. APPLY=1 writes the rows. Add-only and
    # idempotent, so a second run after an apply lists nothing.
    #
    #   kamal app exec --reuse --roles web "bin/rails biteworthy:menus:backfill_implied_bases"
    #   kamal app exec --reuse --roles web "APPLY=1 bin/rails biteworthy:menus:backfill_implied_bases"
    desc "Add the base ingredient a dish name implies (Samosa -> wheat) to dishes that lack it. APPLY=1 writes."
    task backfill_implied_bases: :environment do
      apply = ENV["APPLY"] == "1"
      $stdout.sync = true

      puts "== #{apply ? 'Applying' : 'Dry run'} =="
      result = Menus::ImpliedBaseBackfill.call(apply: apply) do |c|
        added = (c.ingredient_slugs + c.tag_slugs).join(", ")
        puts "  #{c.restaurant_name} — #{c.item_name}: + #{added}"
      end

      if result.reviews.any?
        puts "== Not written: edited since the keyword went live, so a person may have removed the base on purpose. Check each in admin =="
        result.reviews.each do |c|
          puts "  #{c.restaurant_name} — #{c.item_name}: would add #{c.ingredient_slugs.join(', ')}"
          puts "    /admin/restaurants/#{c.restaurant_id} (item #{c.item_id})"
        end
      end
      result.failures.each { |f| puts "  FAILED #{f.item_name} (#{f.item_id}): #{f.error}" }
      puts "== #{result.changes.size} dishes #{apply ? 'changed' : 'would change'}, " \
           "#{result.reviews.size} to review by hand, #{result.failures.size} failed =="
      puts "Re-run with APPLY=1 to write these rows." if !apply && result.changes.any?
    end

    desc "Re-extract all items in a restaurant's most recent ingestion run"
    task :reextract_restaurant, [ :restaurant_id ] => :environment do |_t, args|
      restaurant_id = args[:restaurant_id]

      unless restaurant_id
        puts "ERROR: restaurant_id required"
        puts "Usage: bin/rails biteworthy:menus:reextract_restaurant[123]"
        exit 1
      end

      restaurant = Restaurant.find_by(id: restaurant_id)
      unless restaurant
        puts "ERROR: Restaurant #{restaurant_id} not found"
        exit 1
      end

      run = restaurant.ingestion_runs.order(created_at: :desc).first
      unless run
        puts "ERROR: No ingestion runs found for #{restaurant.name}"
        exit 1
      end

      puts "== Re-extracting #{restaurant.name} (run #{run.id}) =="

      if run.status == "published"
        puts "WARNING: This run is already published."
        puts "Re-extraction will create a NEW draft run and leave the published one untouched."
        puts "After verifying the new run, you can publish it to replace the live menu."
      end

      # Start a new extraction from the same blobs
      if run.menu_blobs.empty?
        puts "ERROR: No menu blobs attached to run #{run.id}"
        exit 1
      end

      new_run = restaurant.ingestion_runs.create!(
        status: "queued",
        source: "re-extraction",
        created_by_user: run.created_by_user
      )

      run.menu_blobs.each do |blob|
        new_run.menu_blobs.attach(blob)
      end

      Ingestion::StartRun.call(new_run)

      puts "Started new extraction: run #{new_run.id}"
      puts "Monitor status at /admin/ingestion_runs/#{new_run.id}"
      puts "== Done =="
    end
  end
end
