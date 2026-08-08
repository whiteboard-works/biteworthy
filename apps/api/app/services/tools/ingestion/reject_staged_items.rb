# frozen_string_literal: true

module Tools
  module Ingestion
    class RejectStagedItems < Tools::Ingestion::Base
      tool_name "reject_staged_items"
      title "Discard scanned dishes"
      description <<~TEXT
        Mark staged dishes as rejected so they never reach the menu. Use this
        for things the extractor got wrong — a section header read as a dish,
        an upsell line, a duplicate.

        Rejected dishes stay in the scan for the audit trail rather than being
        deleted, and `undo_staged_item` puts one back to pending.

        This does not touch the live menu. To remove a dish that is already
        published, undo its acceptance instead.
      TEXT

      input_schema(
        properties: {
          scan_id:  { type: "string", description: "The scan id." },
          item_ids: {
            type: "array", items: { type: "string" },
            description: "Staged dish ids to reject."
          }
        },
        required: %w[scan_id item_ids]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, scan_id:, item_ids:)
        run = find_run!(context, scan_id)

        ids = Array(item_ids).map(&:to_s).reject(&:blank?)
        raise Errors::InvalidArgument, "Pass at least one item_id." if ids.empty?

        items = run.ingestion_items.where(id: ids).to_a
        missing = ids - items.map(&:id)
        raise Errors::NotFound, "No staged dish(es) with id(s): #{missing.join(', ')}." if missing.any?

        # An already-promoted dish is on the live menu; rejecting the staged
        # row would leave the Item behind and the record lying about it.
        promoted = items.select { |i| i.item_id.present? }
        if promoted.any?
          raise Errors::InvalidArgument,
                "#{promoted.size} of those are already on the live menu. " \
                "Use undo_staged_item to take them back off first."
        end

        items.each { |item| item.update!(decision: "rejected", decided_at: Time.current) }

        ok(
          rejected: items.map { |i| { id: i.id, name: untrusted(i.name) } },
          remaining_pending: run.ingestion_items.where(decision: "pending").count
        )
      end
    end
  end
end
