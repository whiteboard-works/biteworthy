# frozen_string_literal: true

module Restaurants
  # Backfills menu sections and item variants for a published restaurant from
  # its stored accepted IngestionItem payloads. Idempotent: never overwrites
  # existing sections or variants that were set manually.
  #
  # Used to repair production data after bugs that dropped section_name or
  # prices_payload at promote, without re-scanning the menu.
  class BackfillStructure
    def initialize(restaurant:, dry_run: false, overwrite_prices: false)
      @restaurant = restaurant
      @dry_run    = dry_run
      @overwrite_prices = overwrite_prices
      @changes    = { sections_created: [], variants_added: [] }
    end

    def call
      ActiveRecord::Base.transaction do
        backfill_sections!
        backfill_variants!
        raise ActiveRecord::Rollback if @dry_run
      end
      @changes
    end

    private

    def backfill_sections!
      menu = Menu.find_or_create_by!(restaurant: @restaurant) do |m|
        m.name = "Main"
        m.position = 0
      end

      # Track sections by name to assign positions based on first appearance
      section_positions = {}
      next_position = 0

      accepted_items.each_with_index do |ingestion_item, item_index|
        next if ingestion_item.section_name.blank?

        # Assign section position based on first appearance in source order
        unless section_positions.key?(ingestion_item.section_name)
          section_positions[ingestion_item.section_name] = next_position
          next_position += 1
        end

        section = MenuSection.find_or_create_by!(menu: menu, name: ingestion_item.section_name) do |s|
          s.position = section_positions[ingestion_item.section_name]
        end

        # Update section position if it already exists (idempotent)
        section.update!(position: section_positions[ingestion_item.section_name]) if section.position != section_positions[ingestion_item.section_name]

        # Count items in this section so far to set position
        section_item_count = accepted_items[0..item_index].count { |ii| ii.section_name == ingestion_item.section_name && ii.item_id }
        item_position = section_item_count - 1

        ingestion_item.item.update!(menu_section_id: section.id, position: item_position)
        @changes[:sections_created] << {
          item_id: ingestion_item.item_id,
          section_name: section.name
        }
      end
    end

    def backfill_variants!
      # Group ingestion items by item_id and pick the latest accepted one per item
      latest_items = accepted_items.group_by(&:item_id)
                                   .transform_values { |items| items.max_by(&:created_at) }

      latest_items.each_value do |ingestion_item|
        # Skip if item already has variants and we're not overwriting
        next if ingestion_item.item.item_variants.any? && !@overwrite_prices
        next if ingestion_item.prices_payload.blank?

        rows = Array(ingestion_item.prices_payload).each_with_index.filter_map do |row, index|
          row = row.with_indifferent_access
          next if row[:price_cents].blank?

          {
            item_id: ingestion_item.item_id,
            size: row[:size],
            price_cents: row[:price_cents],
            currency: row[:currency] || "USD",
            position: index
          }
        end

        if rows.any?
          # If overwriting, delete existing variants first
          ingestion_item.item.item_variants.destroy_all if @overwrite_prices

          ItemVariant.insert_all(rows) if rows.any?
          @changes[:variants_added] << {
            item_id: ingestion_item.item_id,
            item_name: ingestion_item.item.name,
            count: rows.size,
            variants: rows.map { |r| { size: r[:size], price_cents: r[:price_cents], currency: r[:currency] } }
          }
        end
      end
    end

    def accepted_items
      @accepted_items ||= IngestionItem
                          .joins(:item)
                          .where(items: { restaurant_id: @restaurant.id, status: "published" })
                          .where(decision: "accepted")
                          .includes(:item)
    end
  end
end
