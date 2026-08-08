# frozen_string_literal: true

module Tools
  module Ingestion
    # Fix a dish before it reaches the live menu.
    #
    # Fixing data upstream — here, while it is still staged — beats
    # correcting a published dish afterwards, because the correction never
    # has to race a user reading the wrong ingredients.
    class EditStagedItem < Tools::Ingestion::Base
      tool_name "edit_staged_item"
      title "Correct a scanned dish"
      description <<~TEXT
        Correct a staged dish before it is accepted. Editing alone does not
        publish anything; call `accept_staged_items` afterwards.

        Every field is optional and each list you pass REPLACES that list
        wholesale — send the complete set you want stored, not a delta. Omit
        a field to leave it untouched; pass an empty array to clear it.

        Ingredient and tag slugs must come from `search_taxonomy`. Unknown
        slugs are rejected and nothing is saved.

        Adding a missing allergen ingredient here is the highest-value edit
        you can make: an ingredient we never resolved is one the dietary
        filter cannot hide.

        One asymmetry to know: on a dish that updates an existing menu item
        (`updates_existing_item` in list_staged_items), an empty `prices`
        array does NOT clear the live dish's prices. An empty scanned price
        set means "this scan saw no prices", never "this dish is free".
      TEXT

      input_schema(
        properties: {
          item_id:     { type: "string", description: "The staged dish id from list_staged_items." },
          name:        { type: "string", description: "Corrected dish name." },
          description: { type: "string", description: "Corrected description." },
          ingredient_slugs: {
            type: "array", items: { type: "string" },
            description: "Complete replacement ingredient list, as slugs from search_taxonomy."
          },
          tag_slugs: {
            type: "array", items: { type: "string" },
            description: "Complete replacement tag list, as slugs from search_taxonomy."
          },
          prices: {
            type: "array",
            items: {
              type: "object",
              properties: {
                size:        { type: "string", description: 'Size label, e.g. "Large". Omit for a single price.' },
                price_cents: { type: "integer", description: "Price in cents. 1250 = $12.50.", minimum: 0 }
              },
              required: ["price_cents"],
              additionalProperties: false
            },
            description: "Complete replacement price list."
          },
          addons: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name:        { type: "string" },
                price_cents: { type: "integer", minimum: 0 }
              },
              required: ["name"],
              additionalProperties: false
            },
            description: "Complete replacement add-on list (upsells like 'add guacamole')."
          }
        },
        required: ["item_id"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, item_id:, name: nil, description: nil,
                       ingredient_slugs: nil, tag_slugs: nil, prices: nil, addons: nil)
        item = find_staged_item!(context, item_id)

        if item.item_id.present?
          raise Errors::InvalidArgument,
                "That dish was already accepted and is on the live menu. " \
                "Undo it with undo_staged_item first, or edit the live dish instead."
        end

        attrs = {}
        attrs[:name]        = name        unless name.nil?
        attrs[:description] = description unless description.nil?
        attrs[:ingredients_payload] = human_payload(Ingredient, ingredient_slugs, "ingredient") unless ingredient_slugs.nil?
        attrs[:tags_payload]        = human_payload(Tag,        tag_slugs,        "tag")        unless tag_slugs.nil?
        attrs[:prices_payload]      = normalize_prices(prices)  unless prices.nil?
        attrs[:addons_payload]      = normalize_addons(addons)  unless addons.nil?

        raise Errors::InvalidArgument, "Nothing to change — pass at least one field." if attrs.empty?

        # Clearing the unresolved lists is the point of the edit: whatever we
        # could not match, a human has now spoken to.
        attrs[:unresolved_ingredients] = [] if attrs.key?(:ingredients_payload)
        attrs[:unresolved_tags]        = [] if attrs.key?(:tags_payload)

        item.update!(attrs.merge(decision: "edited", decided_at: Time.current))

        ok(dish: staged_item_row(item.reload), next_step: "Call accept_staged_items to put this on the menu.")
      end

      # A human typed these, so they land at the confidence a human edit
      # earns — the promote path then decides confirmed vs suggested from
      # WHO accepted, which is the existing trust model.
      def self.human_payload(model, slugs, label)
        list = Array(slugs).map(&:to_s).reject(&:blank?).uniq
        return [] if list.empty?

        found   = model.where(slug: list).to_a
        missing = list - found.map(&:slug)
        if missing.any?
          raise Errors::InvalidArgument,
                "Unknown #{label} slug(s): #{missing.join(', ')}. Use search_taxonomy to find the right ones."
        end

        found.map { |r| { "slug" => r.slug, "confidence" => 1.0, "source" => "human" } }
      end
      private_class_method :human_payload

      def self.normalize_prices(rows)
        Array(rows).filter_map do |row|
          cents = row["price_cents"] || row[:price_cents]
          next if cents.nil?
          raise Errors::InvalidArgument, "price_cents must be a whole number of cents." unless cents.to_s.match?(/\A\d+\z/)

          { "size" => row["size"] || row[:size], "price_cents" => cents.to_i }.compact
        end
      end
      private_class_method :normalize_prices

      def self.normalize_addons(rows)
        Array(rows).filter_map do |row|
          addon_name = (row["name"] || row[:name]).to_s.strip
          next if addon_name.blank?

          cents = row["price_cents"] || row[:price_cents]
          { "name" => addon_name, "price_cents" => cents&.to_i, "source" => "human" }.compact
        end
      end
      private_class_method :normalize_addons
    end
  end
end
