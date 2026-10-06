# frozen_string_literal: true

module Tools
  module Admin
    # Edit a published item: name, description, status, ingredients, tags,
    # variants, modifiers. Reuses Admin::ItemEditor so validation and join
    # syncing stay in one place.
    class UpdatePublishedItem < Tools::AdminBase
      tool_name "update_published_item"
      title "Edit a published item"
      description <<~TEXT
        Edit a dish that is already on the live menu: name, description,
        status (published/removed), section, position, ingredients, tags,
        variants, and modifiers.

        Ingredients and tags are edited by slug (use search_taxonomy to
        resolve names). An explicit empty array clears that facet; omitting
        the field leaves it alone. New rows default to confirmed / human.
        Pass added_confidence: "suggested" (or "inferred") when a slug is a
        cautionary guess — e.g. tagging an American-Chinese sauced dish
        contains-gluten because it likely has wheat soy sauce. Only rows
        ADDED in that call get the marking; kept rows stay as they are.
        Unverified adds land source: derived so a later remap cannot treat
        them as confirmed. The dish's own confidence is then re-derived
        from the weakest current join (a suggested contains-gluten tag
        pulls a confirmed dish down to suggested).

        status: "removed" is the admin unpublish — the item stays in the
        database with its reviews, but is hidden from the public menu.

        Dish-level confidence is NOT settable here — it only moves through
        that weakest-row re-derive, promote!, and confirm_restaurant_data.
      TEXT

      input_schema(
        properties: {
          item_id: {
            type: "string",
            description: "Item UUID."
          },
          name: { type: "string" },
          description: { type: "string" },
          status: {
            type: "string",
            enum: Item::STATUSES,
            description: "#{Item::STATUSES.join(', ')}. removed = admin unpublish."
          },
          menu_section_id: {
            type: "string",
            description: "Menu section UUID. Must belong to the same restaurant."
          },
          position: {
            type: "integer",
            description: "Sort position within the section."
          },
          ingredient_slugs: {
            type: "array",
            items: { type: "string" },
            description: "Ingredient slugs. Replaces current list. Empty array = clear."
          },
          tag_slugs: {
            type: "array",
            items: { type: "string" },
            description: "Tag slugs. Replaces current list. Empty array = clear."
          },
          added_confidence: {
            type: "string",
            enum: Item::CONFIDENCE,
            description: "Confidence for rows ADDED in this call only " \
                         "(confirmed|suggested|inferred). Default confirmed, " \
                         "which keeps the existing human-verified marking. " \
                         "suggested/inferred write source derived so they stay " \
                         "unverified under the confidence mapper."
          },
          variants: {
            type: "array",
            items: {
              type: "object",
              properties: {
                size: { type: "string" },
                price_cents: { anyOf: [ { type: "integer", minimum: 0 }, { type: "string" } ] },
                currency: { type: "string" }
              }
            },
            description: "Size variants. Replaces current list."
          },
          modifiers: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                kind: { type: "string" },
                price_cents: { anyOf: [ { type: "integer", minimum: 0 }, { type: "string" } ] }
              }
            },
            description: "Add-ons/modifiers. Replaces current list."
          }
        },
        required: [ "item_id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { |args| args[:status] == "removed" }

      running_description { |args| "Updating item #{args[:item_id]}" }

      def self.perform(context:, item_id:, **attrs)
        context.admin!
        item = Item.find(item_id)

        # Validate status
        if attrs.key?(:status) && !Item::STATUSES.include?(attrs[:status].to_s)
          raise Errors::InvalidArgument, "Invalid status. Allowed: #{Item::STATUSES.join(', ')}"
        end

        # Validate prices
        validate_prices!(attrs)

        # Delegate to ItemEditor
        ::Admin::ItemEditor.new(item).call(attrs)

        ok(serialize_item(item))
      rescue ::Admin::ItemEditor::UnknownSlug => e
        raise Errors::InvalidArgument, "Unknown #{e.kind} slugs: #{e.slugs.join(', ')}"
      rescue ::Admin::ItemEditor::InvalidAddedConfidence => e
        raise Errors::InvalidArgument,
              "Invalid added_confidence: #{e.value}. Allowed: #{Item::CONFIDENCE.join(', ')}"
      rescue ::Admin::ItemEditor::ForeignSection
        raise Errors::InvalidArgument, "menu_section_id must belong to the same restaurant"
      end

      def self.validate_prices!(attrs)
        bad = %i[variants modifiers].flat_map do |key|
          rows = attrs[key]
          next [] unless rows.is_a?(Array)

          rows.filter_map do |row|
            next unless row.respond_to?(:[])
            value = row[:price_cents] || row["price_cents"]
            next if value.nil? || value.to_s.strip.empty?
            value.to_s unless value.to_s.match?(/\A\d+\z/)
          end
        end

        raise Errors::InvalidArgument, "Invalid price_cents: #{bad.join(', ')}" if bad.any?
      end
      private_class_method :validate_prices!

      def self.serialize_item(item)
        item.reload
        {
          id: item.id,
          restaurant_id: item.restaurant_id,
          name: item.name,
          description: item.description,
          status: item.status,
          confidence: item.confidence,
          position: item.position,
          menu_section_id: item.menu_section_id,
          ingredients: item.ingredients.sort_by(&:name).map { |i| { slug: i.slug, name: i.name } },
          tags: item.tags.sort_by(&:name).map { |t| { slug: t.slug, name: t.name } },
          variants: item.item_variants.sort_by { |v| v.position.to_i }.map { |v|
            { size: v.size, price_cents: v.price_cents, currency: v.currency }
          },
          modifiers: item.item_modifiers.sort_by(&:name).map { |m|
            { name: m.name, kind: m.kind, price_cents: m.price_cents }
          }
        }
      end
      private_class_method :serialize_item
    end
  end
end
