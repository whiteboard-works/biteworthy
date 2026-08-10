# frozen_string_literal: true

module Tools
  module Restaurants
    class ConfirmRestaurantData < Tools::AdminBase
      tool_name "confirm_restaurant_data"
      title "Graduate a restaurant's community data to confirmed"
      description <<~TEXT
        Promote every human-entered "suggested" ingredient and tag at a
        restaurant to "confirmed", and graduate the dishes whose associations
        are then all confirmed.

        This is what makes a restaurant visible to strict-mode users — the
        people filtering for a real allergy. Do not call it to tidy up a
        status field. Call it only when a human has actually checked the data,
        and say so: after this, someone with a severe allergy will be shown
        these dishes as safe.

        AI-suggested associations are deliberately left alone; a dish still
        carrying one stays "suggested" no matter what else graduated. Cannot
        be undone through the tool layer.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant slug or UUID." }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # The description above says it: cannot be undone through the tool
      # layer, and what it buys is visibility to strict-mode users — the
      # people filtering for a real allergy. There is no later edit that
      # un-tells someone a dish was safe.
      unrecoverable_when { true }

      def self.perform(context:, restaurant:)
        context.admin!
        record = find_restaurant!(restaurant)
        counts = record.confirm_community_associations!

        ok(
          restaurant: restaurant_row(record),
          confirmed:  counts,
          still_suggested_items: record.items.where(confidence: "suggested").count
        )
      end
    end
  end
end
