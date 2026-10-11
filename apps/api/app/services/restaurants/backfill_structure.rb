# frozen_string_literal: true

module Restaurants
  # Backfills menu sections and item variants for a published restaurant from
  # its stored accepted IngestionItem payloads. Idempotent: never overwrites
  # existing sections or variants that were set manually.
  #
  # Used to repair production data after bugs that dropped section_name or
  # prices_payload at promote, without re-scanning the menu.
  #
  # `reorder: true` is a second, narrower pass for restaurants whose dishes
  # already have sections (the earlier backfill assigned them in processing
  # order, so every section position and every item position is wrong). It
  # rewrites `menu_sections.position` and `items.position` from source-menu
  # order and never moves a dish, creates a section, or renames one.
  class BackfillStructure
    def initialize(restaurant:, dry_run: false, overwrite_prices: false, reorder: false)
      @restaurant = restaurant
      @dry_run    = dry_run
      @overwrite_prices = overwrite_prices
      @reorder = reorder
      @changes    = {
        sections_created: [],
        variants_added: [],
        sections_reordered: [],
        items_reordered: []
      }
    end

    def call
      ActiveRecord::Base.transaction do
        backfill_sections!
        backfill_variants!
        reorder_positions! if @reorder
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

      # First appearance in source-menu order (ingestion_items.position).
      section_positions = {}
      next_position = 0
      section_item_counts = Hash.new(0)

      accepted_items.each do |ingestion_item|
        next if ingestion_item.section_name.blank?

        item = ingestion_item.item
        # Manual curation wins: never move a dish that already has a section.
        next if item.menu_section_id.present?

        unless section_positions.key?(ingestion_item.section_name)
          section_positions[ingestion_item.section_name] = next_position
          next_position += 1
        end

        desired = section_positions[ingestion_item.section_name]
        section = MenuSection.find_or_create_by!(menu: menu, name: ingestion_item.section_name) do |s|
          s.position = desired
        end
        section.update!(position: desired) if section.position != desired

        item_position = section_item_counts[section.id]
        section_item_counts[section.id] += 1

        item.update!(menu_section_id: section.id, position: item_position)
        @changes[:sections_created] << {
          item_id: item.id,
          section_name: section.name
        }
      end
    end

    def backfill_variants!
      latest_accepted_per_item.each_value do |ingestion_item|
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

    # Rewrite section and item positions from source-menu order. The walk
    # uses the latest accepted IngestionItem per dish; the section a dish
    # already belongs to is the one that counts (never the payload name).
    def reorder_positions!
      sourced_section_ids = []
      sourced_items_by_section = Hash.new { |h, k| h[k] = [] }
      seen_item_ids = Set.new

      source_ordered_latest_items.each do |ingestion_item|
        item = ingestion_item.item
        next if item.menu_section_id.blank?

        section_id = item.menu_section_id
        sourced_section_ids << section_id unless sourced_section_ids.include?(section_id)
        next if seen_item_ids.include?(item.id)

        sourced_items_by_section[section_id] << item
        seen_item_ids << item.id
      end

      Menu.where(restaurant: @restaurant).includes(:menu_sections).find_each do |menu|
        sections = menu.menu_sections.sort_by { |section| [ section.position.to_i, section.created_at ] }
        sourced = sourced_section_ids.filter_map { |id| sections.find { |section| section.id == id } }
        unsourced = sections - sourced

        (sourced + unsourced).each_with_index do |section, index|
          old_position = section.position
          section.update!(position: index) if old_position != index
          @changes[:sections_reordered] << {
            id: section.id,
            name: section.name,
            old_position: old_position,
            new_position: index
          }
        end
      end

      published_in_sections = Item
                              .where(restaurant_id: @restaurant.id, status: "published")
                              .where.not(menu_section_id: nil)
                              .order(:position, :created_at)
                              .to_a

      published_in_sections.group_by(&:menu_section_id).each do |section_id, items|
        sourced = sourced_items_by_section[section_id] || []
        sourced_ids = sourced.map(&:id)
        unsourced = items.reject { |item| sourced_ids.include?(item.id) }

        (sourced + unsourced).each_with_index do |item, index|
          old_position = item.position
          item.update!(position: index) if old_position != index
          @changes[:items_reordered] << {
            id: item.id,
            name: item.name,
            section_id: section_id,
            old_position: old_position,
            new_position: index
          }
        end
      end
    end

    def source_ordered_latest_items
      latest_accepted_per_item.values.sort_by do |ingestion_item|
        [ ingestion_item.position.nil? ? 1 : 0, ingestion_item.position.to_i, ingestion_item.created_at ]
      end
    end

    def latest_accepted_per_item
      @latest_accepted_per_item ||= accepted_items.group_by(&:item_id)
                                                  .transform_values { |rows| rows.max_by(&:created_at) }
    end

    def accepted_items
      @accepted_items ||= IngestionItem
                          .joins(:item)
                          .where(items: { restaurant_id: @restaurant.id, status: "published" })
                          .where(decision: "accepted")
                          .includes(:item)
                          .order(Arel.sql("ingestion_items.position ASC NULLS LAST, ingestion_items.created_at ASC"))
    end
  end
end
