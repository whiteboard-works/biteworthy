# frozen_string_literal: true

namespace :biteworthy do
  namespace :menus do
    desc "Identify items that may need re-review for new wheat-based ingredients"
    task audit_celiac_safety: :environment do
      wheat = Ingredient.find_by(slug: "grain-wheat")
      unless wheat
        warn "ERROR: grain-wheat ingredient not found. Run db:seed first."
        exit 1
      end

      wheat_keywords = %w[
        hotcake pancake biscuit muffin gravy roux batter breading
        samosa relleno tempura
      ]

      warn "== Auditing published items for hidden wheat sources =="
      warn "   Keywords: #{wheat_keywords.join(', ')}"
      warn ""

      issues = []

      Item.published.includes(:restaurant, :ingredients).find_each do |item|
        text = "#{item.name} #{item.description}".downcase
        matched_keywords = wheat_keywords.select { |kw| text.include?(kw) }
        next if matched_keywords.empty?

        has_wheat = item.ingredients.any? { |ing| ing.path.to_s.start_with?("grain.wheat") }
        next if has_wheat

        issues << {
          restaurant: item.restaurant.name,
          item: item.name,
          keywords: matched_keywords,
          url: "/admin/restaurants/#{item.restaurant.id}/items/#{item.id}"
        }
      end

      if issues.any?
        warn "Found #{issues.count} items that may need wheat ingredients:"
        warn ""
        issues.each do |issue|
          warn "  #{issue[:restaurant]} — #{issue[:item]}"
          warn "    Matched: #{issue[:keywords].join(', ')}"
          warn "    Admin: #{issue[:url]}"
          warn ""
        end
      else
        warn "No issues found! All keyword-matched items have wheat ingredients."
      end
    end

    # The fix the audit above only reports. Dry run by default: it lists
    # every dish it would change. APPLY=1 writes the rows. Add-only and
    # idempotent, so a second run after an apply lists nothing.
    #
    #   kamal app exec --reuse --roles web "bin/rails biteworthy:menus:backfill_implied_bases"
    #   kamal app exec --reuse --roles web "APPLY=1 bin/rails biteworthy:menus:backfill_implied_bases"
    desc "Add the gluten rows today's rules imply (Samosa, breaded, soy sauce) to dishes promoted before those rules. APPLY=1 writes."
    task backfill_implied_bases: :environment do
      apply = ENV["APPLY"] == "1"
      $stdout.sync = true

      puts "== #{apply ? 'Applying' : 'Dry run'} =="
      result = Menus::ImpliedBaseBackfill.call(apply: apply) do |c|
        added = (c.ingredient_slugs + c.tag_slugs).join(", ")
        puts "  #{c.restaurant_name} — #{c.item_name}: + #{added}"
      end

      if result.reviews.any?
        puts "== Not written: edited since the rule went live, so a person may have removed the row on purpose. Check each in admin =="
        result.reviews.each do |c|
          puts "  #{c.restaurant_name} — #{c.item_name}: would add #{(c.ingredient_slugs + c.tag_slugs).join(', ')}"
          puts "    /admin/restaurants/#{c.restaurant_id} (item #{c.item_id})"
        end
      end
      result.failures.each { |f| puts "  FAILED #{f.item_name} (#{f.item_id}): #{f.error}" }
      puts "== #{result.changes.size} dishes #{apply ? 'changed' : 'would change'}, " \
           "#{result.reviews.size} to review by hand, #{result.failures.size} failed =="
      puts "Re-run with APPLY=1 to write these rows." if !apply && result.changes.any?
    end

    desc "Re-extract a restaurant's menu from its latest inputs (creates a new scan, no auto-accept)"
    task :reextract_restaurant, [ :restaurant_uuid ] => :environment do |_t, args|
      restaurant_uuid = args[:restaurant_uuid]
      dry_run = ENV.fetch("DRY_RUN", "true") == "true"

      unless restaurant_uuid
        warn "ERROR: restaurant_uuid required"
        warn "Usage: bin/rails biteworthy:menus:reextract_restaurant[<uuid>] [DRY_RUN=false]"
        exit 1
      end

      restaurant = Restaurant.find_by(id: restaurant_uuid)
      unless restaurant
        warn "ERROR: Restaurant #{restaurant_uuid} not found"
        exit 1
      end

      result = Admin::ReextractRestaurant.call(restaurant: restaurant, dry_run: dry_run)
      unless result.ok
        warn "ERROR: #{result.message}"
        exit 1
      end

      warn result.message
      if dry_run
        warn "To proceed: bin/rails biteworthy:menus:reextract_restaurant[#{restaurant_uuid}] DRY_RUN=false"
      end
    end
  end
end
