# frozen_string_literal: true

module Tools
  module Admin
    # List all items at a restaurant, including removed ones. Same data the
    # admin items endpoint returns, for editing published dishes.
    class ListRestaurantItems < Tools::AdminBase
      tool_name "list_restaurant_items"
      title "List restaurant items (admin)"
      description <<~TEXT
        List all items at a restaurant, including removed ones that public
        endpoints filter out.

        Returns id, name, description, status, confidence, section, position,
        ingredients (with slugs for editing), tags, variants, and modifiers.

        Use this to find items to edit with update_published_item.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          status: {
            type: "string",
            enum: Item::STATUSES,
            description: "Filter by status: #{Item::STATUSES.join(', ')}. Omit for all."
          }
        },
        required: [ "restaurant" ]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Listing items" }

      def self.perform(context:, restaurant:, status: nil)
        context.admin!
        record = find_restaurant!(restaurant)
        scope = Item.where(restaurant_id: record.id)
                    .includes(:item_variants, :item_modifiers, :ingredients, :tags, :menu_section)
                    .order(:menu_section_id, :position, :created_at, :id)

        scope = scope.where(status: status) if Item::STATUSES.include?(status.to_s)

        items = scope.limit(200).to_a
        ok(
          restaurant: { id: record.id, slug: record.slug, name: record.name },
          count: items.size,
          items: items.map { |item| serialize_item(item) }
        )
      end

      def self.serialize_item(item)
        {
          id: item.id,
          name: item.name,
          description: item.description,
          status: item.status,
          confidence: item.confidence,
          position: item.position,
          menu_section_id: item.menu_section_id,
          section_name: item.menu_section&.name,
          ingredients: item.ingredients.sort_by(&:name).map { |i|
            { id: i.id, slug: i.slug, name: i.name }
          },
          tags: item.tags.sort_by(&:name).map { |t|
            { id: t.id, slug: t.slug, name: t.name, family: t.family }
          },
          variants: item.item_variants.sort_by { |v| v.position.to_i }.map { |v|
            { id: v.id, size: v.size, price_cents: v.price_cents, currency: v.currency }
          },
          modifiers: item.item_modifiers.sort_by(&:name).map { |m|
            { id: m.id, name: m.name, kind: m.kind, price_cents: m.price_cents }
          }
        }
      end
      private_class_method :serialize_item
    end
  end
end
