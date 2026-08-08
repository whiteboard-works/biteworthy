# frozen_string_literal: true

module Tools
  module Items
    class EditItem < Tools::AdminBase
      tool_name "edit_item"
      title "Edit a live dish"
      description <<~TEXT
        Fix a published dish: its name, description, status, which section it
        sits in, its ingredients and tags, its sizes and prices, and its
        add-ons. Omitted fields are left alone.

        `ingredient_slugs` and `tag_slugs` REPLACE the dish's lists — send the
        full set you want, not just the additions. Resolve every slug with
        `search_taxonomy` first; one unknown slug rejects the whole call
        rather than silently dropping it.

        Removing an ingredient here un-hides the dish for everyone avoiding
        it, immediately and with no review step. Only do it when you know the
        dish does not contain it. Adding is the safe direction.

        Anything you add lands as human-confirmed, which means it outranks
        anything a future menu scan says. `variants` and `modifiers` also
        replace wholesale — send the full list.

        `confidence` on the dish is not settable here; it moves only when data
        is verified (`confirm_restaurant_data`), because strict-mode
        visibility rides on it.
      TEXT

      input_schema(
        properties: {
          item_id:     { type: "string", description: "The dish's UUID, from get_menu_structure." },
          name:        { type: "string" },
          description: { type: "string" },
          status:      { type: "string", description: "'removed' is the unpublish.", enum: Item::STATUSES },
          menu_section_id: {
            type: "string",
            description: "Move the dish to this section. Must belong to the same restaurant. Empty string unfiles it."
          },
          ingredient_slugs: {
            type: "array", items: { type: "string" },
            description: "The dish's FULL ingredient list after the edit."
          },
          tag_slugs: {
            type: "array", items: { type: "string" },
            description: "The dish's FULL tag list after the edit."
          },
          variants: {
            type: "array",
            description: "Sizes and prices, in menu order. Replaces the existing set.",
            items: {
              type: "object",
              properties: {
                size:        { type: "string", description: "e.g. 'Large'. Optional." },
                price_cents: { type: "integer", description: "Whole cents. Omit for 'market price'." },
                currency:    { type: "string", description: "Defaults to USD." }
              }
            }
          },
          modifiers: {
            type: "array",
            description: "Add-ons and options. Replaces the existing set.",
            items: {
              type: "object",
              properties: {
                name:        { type: "string" },
                kind:        { type: "string", enum: ItemModifier::KINDS },
                price_cents: { type: "integer" }
              },
              required: ["name"]
            }
          }
        },
        required: ["item_id"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      EDITABLE = %i[
        name description status menu_section_id
        ingredient_slugs tag_slugs variants modifiers
      ].freeze

      def self.perform(context:, item_id:, **fields)
        context.admin!
        item  = Item.find(item_id)
        attrs = fields.slice(*EDITABLE)
        raise Errors::InvalidArgument, "Pass at least one field to change." if attrs.empty?

        validate_status!(attrs[:status]) if attrs.key?(:status)
        validate_prices!(attrs)

        ::Admin::ItemEditor.new(item).call(attrs)
        ok(item_row(item.reload).merge(changed: attrs.keys))
      rescue ::Admin::ItemEditor::UnknownSlug => e
        raise Errors::InvalidArgument,
              "Unknown #{e.kind} slugs: #{e.slugs.join(', ')}. Resolve them with search_taxonomy."
      rescue ::Admin::ItemEditor::ForeignSection
        raise Errors::InvalidArgument, "That section belongs to a different restaurant."
      end

      class << self
        private

        def validate_status!(status)
          return if Item::STATUSES.include?(status)

          raise Errors::InvalidArgument, "status must be one of: #{Item::STATUSES.join(', ')}."
        end

        # A price is whole cents. "4.50" would cast to 4, quietly turning a
        # $4.50 taco into four cents on a live menu.
        def validate_prices!(attrs)
          bad = %i[variants modifiers].flat_map do |key|
            Array(attrs[key]).filter_map do |row|
              value = row[:price_cents] || row["price_cents"]
              next if value.nil? || value.to_s.strip.empty?
              value.to_s unless value.to_s.match?(/\A\d+\z/)
            end
          end
          return if bad.empty?

          raise Errors::InvalidArgument, "price_cents must be whole cents: #{bad.join(', ')}"
        end

        def item_row(item)
          {
            id:          item.id,
            name:        untrusted(item.name),
            description: untrusted(item.description),
            status:      item.status,
            confidence:  item.confidence,
            section:     item.menu_section&.name,
            ingredients: item.ingredients.map(&:slug).sort,
            tags:        item.tags.map(&:slug).sort,
            variants:    item.item_variants.sort_by { |v| v.position.to_i }.map do |v|
              { size: v.size, price_cents: v.price_cents, currency: v.currency }
            end,
            modifiers: item.item_modifiers.map { |m| { name: m.name, kind: m.kind, price_cents: m.price_cents } }
          }
        end
      end
    end
  end
end
