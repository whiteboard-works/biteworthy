# frozen_string_literal: true

module Tools
  module Structure
    class GetMenuStructure < Tools::AdminBase
      tool_name "get_menu_structure"
      title "A restaurant's menus, sections, and every dish"
      description <<~TEXT
        The admin view of a restaurant: its menus, the sections inside them,
        and every dish including drafts and removed ones.

        This is not `get_menu`. `get_menu` answers "what can this person eat"
        against published data and a filter; this answers "what is here and
        what state is it in", applies no filter, and is where you get the id
        of an unpublished dish so `edit_item` can reach it.

        `confidence: "suggested"` means nobody has verified that dish's
        ingredients. Dishes with no section are real and orderable — they just
        have not been filed yet.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant slug or UUID." },
          include_items: {
            type: "boolean",
            description: "Include the dishes, not just the sections. Default true."
          }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      MAX_ITEMS = 500

      def self.perform(context:, restaurant:, include_items: true)
        context.admin!
        record = find_restaurant!(restaurant)

        menus = record.menus.order(:position, :name).includes(:menu_sections)
        items = include_items ? items_by_section(record) : {}

        ok({
          restaurant:  restaurant_row(record),
          menus:       menus.map { |menu| menu_row(menu, items) },
          unsectioned: (items[nil] if include_items),
          item_count:  record.items.count
        }.compact)
      end

      def self.menu_row(menu, items)
        {
          id:       menu.id,
          name:     menu.name,
          position: menu.position,
          sections: menu.menu_sections.sort_by { |s| [s.position.to_i, s.name.to_s] }.map do |section|
            {
              id:       section.id,
              name:     section.name,
              position: section.position,
              items:    items[section.id]
            }.compact
          end
        }
      end
      private_class_method :menu_row

      # One query for the whole restaurant rather than one per section —
      # a scanned menu routinely has 15 sections.
      def self.items_by_section(restaurant)
        restaurant.items.order(:name).limit(MAX_ITEMS).group_by(&:menu_section_id).transform_values do |rows|
          rows.map do |item|
            {
              id: item.id, name: untrusted(item.name),
              status: item.status, confidence: item.confidence
            }
          end
        end
      end
      private_class_method :items_by_section
    end
  end
end
