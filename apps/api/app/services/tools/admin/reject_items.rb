# frozen_string_literal: true

module Tools
  module Admin
    # Reject staged items — "not on the menu". Rejected dishes stay in the
    # scan for audit and count toward the publish threshold, but never promote
    # to the live menu.
    class RejectItems < Tools::AdminBase
      tool_name "reject_items"
      title "Reject staged items (admin)"
      description <<~TEXT
        Mark staged dishes as "not on the menu" so they are excluded from
        publish.

        Rejected items stay in the scan for the audit trail and count toward
        the 80% threshold for auto-publishing the restaurant, but never
        promote to the live menu.

        Reversible by changing decision back to pending and accepting.
      TEXT

      input_schema(
        properties: {
          scan_id: { type: "string" },
          item_ids: {
            type: "array",
            items: { type: "string" },
            description: "Staged item ids to reject."
          }
        },
        required: %w[scan_id item_ids]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { "Rejecting items" }

      def self.perform(context:, scan_id:, item_ids:)
        # Delegate to the existing tool
        Tools::Ingestion::RejectStagedItems.perform(
          context: context,
          scan_id: scan_id,
          item_ids: item_ids
        )
      end
    end
  end
end
