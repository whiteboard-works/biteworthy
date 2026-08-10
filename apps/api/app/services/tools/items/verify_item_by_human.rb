# frozen_string_literal: true

module Tools
  module Items
    class VerifyItemByHuman < Tools::Base
      tool_name "verify_item_by_human"
      title "Mark a dish as verified by a human"
      description "Verify that a published dish is correct and accurate. This marks the dish as human-verified in the system's audit trail."

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
        item = Item.find(item_id)
        item.mark_human_verified!(context.user)
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
