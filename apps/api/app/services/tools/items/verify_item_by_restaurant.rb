# frozen_string_literal: true

module Tools
  module Items
    class VerifyItemByRestaurant < Tools::AdminBase
      tool_name "verify_item_by_restaurant"
      title "Mark a dish as verified by the restaurant"
      description <<~TEXT
        Verify that a published dish is correct and accurate as the restaurant owner.
        This marks the dish as restaurant-verified and locks it from further edits
        (except by the restaurant that verified it or a super admin).
      TEXT

      input_schema(
        properties: {
          item_id: { type: "string", description: "The dish's UUID, from get_menu_structure." }
        },
        required: ["item_id"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      unrecoverable_when { false }

      def self.perform(context:, item_id:)
        context.admin!
        item = Item.find(item_id)
        item.mark_restaurant_verified!(context.user)
        ok(verification_row(item))
      end

      class << self
        private

        def verification_row(item)
          {
            id: item.id,
            name: untrusted(item.name),
            human_verified: item.human_verified?,
            human_verified_at: item.human_verified_at,
            restaurant_verified: item.restaurant_verified?,
            restaurant_verified_at: item.restaurant_verified_at
          }
        end
      end
    end
  end
end
