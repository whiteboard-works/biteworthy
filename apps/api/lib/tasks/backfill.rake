# frozen_string_literal: true

namespace :backfill do
  desc "Backfill menu sections and item variants from accepted ingestion payloads"
  task structure: :environment do
    restaurant_id = ENV["RESTAURANT_ID"]
    dry_run       = ENV["DRY_RUN"] == "true"

    unless restaurant_id
      puts "Usage: RESTAURANT_ID=<uuid> [DRY_RUN=true] bin/rails backfill:structure"
      exit 1
    end

    restaurant = Restaurant.find_by(id: restaurant_id)
    unless restaurant
      puts "Restaurant #{restaurant_id} not found"
      exit 1
    end

    puts "Backfilling structure for #{restaurant.name} (#{restaurant.id})"
    puts "DRY RUN MODE" if dry_run

    result = Restaurants::BackfillStructure.new(restaurant: restaurant, dry_run: dry_run).call

    puts "\nResults:"
    puts "  Sections created: #{result[:sections_created].size}"
    result[:sections_created].each do |change|
      puts "    - Item #{change[:item_id]}: #{change[:section_name]}"
    end

    puts "  Variants added: #{result[:variants_added].sum { |v| v[:count] }}"
    result[:variants_added].each do |change|
      puts "    - Item #{change[:item_id]}: #{change[:count]} variants"
    end

    puts "\n✓ Complete" unless dry_run
  end
end
