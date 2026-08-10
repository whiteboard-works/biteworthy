# frozen_string_literal: true

module Tools
  module Ingestion
    # The safety net behind accept. Without this, a wrong accept means
    # editing a live menu by hand to undo it.
    class UndoStagedItem < Tools::Ingestion::Base
      tool_name "undo_staged_item"
      title "Undo a decision on a scanned dish"
      description <<~TEXT
        Put a staged dish back to pending, reversing an accept or a reject.

        Undoing an accept also reverses what it did to the live menu: a dish
        that was created is deleted, and a dish that was UPDATED is restored
        to its previous description, prices, and associations.

        One caveat worth telling the user about: restoring an update is
        last-writer-wins. If someone edited that dish through the admin UI
        after the accept, undo overwrites their edit with the pre-accept
        state.
      TEXT

      input_schema(
        properties: {
          item_id: { type: "string", description: "The staged dish id." }
        },
        required: ["item_id"]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # The undo itself. Re-accepting is the way back, and the tool says out
      # loud that restoring an update is last-writer-wins.
      unrecoverable_when { false }

      def self.perform(context:, item_id:)
        item = find_staged_item!(context, item_id)

        if item.pending?
          raise Errors::InvalidArgument, "That dish is already pending — there is nothing to undo."
        end

        was_promoted = item.item_id.present?
        item.undo!

        ok(
          dish: staged_item_row(item.reload),
          removed_from_live_menu: was_promoted
        )
      end
    end
  end
end
