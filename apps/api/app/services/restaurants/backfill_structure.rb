# frozen_string_literal: true

module Restaurants
  # Backfills menu sections and item variants for a published restaurant from
  # its stored accepted IngestionItem payloads. Idempotent: never overwrites
  # existing sections or variants that were set manually.
  #
  # Used to repair production data after bugs that dropped section_name or
  # prices_payload at promote, without re-scanning the menu.
  class BackfillStructure
    def initialize(restaurant:, dry_run: false)
      @restaurant = restaurant
      @dry_run    = dry_run
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

      accepted_items.each do |ingestion_item|
        next if ingestion_item.section_name.blank?
        next if ingestion_item.item.menu_section_id.present?

        section = MenuSection.find_or_create_by!(menu: menu, name: ingestion_item.section_name) do |s|
          s.position = menu.menu_sections.maximum(:position).to_i + 1
        end

        ingestion_item.item.update!(menu_section_id: section.id)
        @changes[:sections_created] << {
          item_id: ingestion_item.item_id,
          section_name: section.name
        }
      end
    end

    def backfill_variants!
      accepted_items.each do |ingestion_item|
        next if ingestion_item.item.item_variants.any?
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
          ItemVariant.insert_all(rows)
          @changes[:variants_added] << {
            item_id: ingestion_item.item_id,
            count: rows.size
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
