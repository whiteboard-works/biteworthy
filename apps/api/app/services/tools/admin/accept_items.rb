# frozen_string_literal: true

module Tools
  module Admin
    # Accept staged items, publishing them to the live menu. When an admin
    # accepts, associations are stamped "confirmed" and visible to strict-mode
    # users. Same logic as the regular accept tool and the REST endpoint.
    class AcceptItems < Tools::AdminBase
      tool_name "accept_items"
      title "Accept staged items (admin)"
      description <<~TEXT
        Accept staged dishes from a scan and publish them to the restaurant's
        live menu.

        When an admin accepts, item associations (ingredients/tags) are
        recorded as "confirmed" and visible to strict-mode/allergy users. This
        is the confidence promotion that makes dishes safe to show.

        Pass item_ids for specific dishes, or all: true to accept every
        pending dish. Prefer item_ids unless the user explicitly asked for all.

        This uses the same 80% publish threshold as the regular flow: when
        enough dishes are accepted, the restaurant auto-publishes.

        Reversible with undo_staged_item.
      TEXT

      input_schema(
        properties: {
          scan_id: { type: "string" },
          item_ids: {
            type: "array",
            items: { type: "string" },
            description: "Staged item ids to accept."
          },
          all: {
            type: "boolean",
            description: "Accept all pending items. Only when explicitly requested."
          }
        },
        required: [ "scan_id" ]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { "Accepting items" }

      def self.perform(context:, scan_id:, item_ids: nil, all: false)
        context.admin!
        # Delegate to the existing tool — same logic, same validations
        Tools::Ingestion::AcceptStagedItems.perform(
          context: context,
          scan_id: scan_id,
          item_ids: item_ids,
          all: all
        )
      end
    end
  end
end
