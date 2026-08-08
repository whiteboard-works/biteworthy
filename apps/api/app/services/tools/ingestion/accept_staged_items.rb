# frozen_string_literal: true

module Tools
  module Ingestion
    # The tool that puts food on a live menu. Everything upstream is staging;
    # this is the commit.
    class AcceptStagedItems < Tools::Ingestion::Base
      tool_name "accept_staged_items"
      title "Publish scanned dishes to the menu"
      description <<~TEXT
        Accept staged dishes and put them on the restaurant's live menu.

        THIS IS THE STEP THAT PUBLISHES. Confirm with the user before calling
        it. Show them what they are accepting first — especially any dish
        whose `updates_existing_item` is set, because accepting that EDITS a
        dish already on the menu instead of adding a new one.

        Pass `item_ids` for specific dishes, or `all: true` to accept every
        still-pending dish in the scan. Prefer `item_ids` unless the user
        explicitly asked for all of them; `all: true` on a scan they have not
        reviewed publishes unverified data.

        Trust: when an admin accepts, associations are recorded as confirmed
        and are visible to strict-mode users. When a regular contributor
        accepts their own scan, associations are recorded as suggested —
        live for most people, hidden from strict-mode users until an admin
        confirms them. Say which applies if the user asks why a dish is not
        showing up for them.

        Reversible with `undo_staged_item`.
      TEXT

      input_schema(
        properties: {
          scan_id:  { type: "string", description: "The scan id." },
          item_ids: {
            type: "array", items: { type: "string" },
            description: "Staged dish ids to accept."
          },
          all: {
            type: "boolean",
            description: "Accept every still-pending dish in the scan. Only when the user asked for that."
          }
        },
        required: ["scan_id"]
      )

      # destructive_hint: writes to a live menu, and a client that surfaces
      # this hint should be asking the user first.
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      running_description { "Publishing the dishes to the menu" }

      def self.perform(context:, scan_id:, item_ids: nil, all: false)
        user = context.user!
        run  = find_run!(context, scan_id)

        items = select_items(run, item_ids, all)
        raise Errors::InvalidArgument, "Nothing to accept — pass item_ids, or all: true." if items.empty?

        accepted = []
        failed   = []

        items.each do |item|
          accepted << accept_one(run, item, user)
        rescue StandardError => e
          # One bad dish must not abandon the rest half-published. Report it
          # and keep going, then tell the model exactly what didn't land.
          Rails.logger.error("accept_staged_items: IngestionItem##{item.id} failed: #{e.class} #{e.message}")
          failed << { id: item.id, name: item.name, error: e.message }
        end

        run.maybe_publish!
        run.reload

        ok(
          accepted:  accepted,
          failed:    failed.presence,
          restaurant_published: run.restaurant&.status == "published",
          remaining_pending: run.ingestion_items.where(decision: "pending").count
        )
      end

      def self.select_items(run, item_ids, all)
        return run.ingestion_items.where(decision: "pending").order(:position).to_a if all

        ids = Array(item_ids).map(&:to_s).reject(&:blank?)
        return [] if ids.empty?

        found = run.ingestion_items.where(id: ids).order(:position).to_a
        missing = ids - found.map(&:id)
        raise Errors::NotFound, "No staged dish(es) with id(s): #{missing.join(', ')}." if missing.any?

        found
      end
      private_class_method :select_items

      # Promote now when the run is enriched; otherwise record the acceptance
      # and let the resolve pass promote at :staged. An Item must never go
      # live without its ingredient payload — that would be a dish on a
      # filtered menu with nothing to filter on.
      def self.accept_one(run, item, user)
        if run.staged? || run.published?
          promoted = item.promote!(decided_by: user)
          { id: item.id, name: untrusted(item.name), item_id: promoted&.id,
            updated_existing: item.matched_item_id.present? && promoted&.id == item.matched_item_id }
        else
          item.update!(decision: "accepted", decided_at: Time.current)
          { id: item.id, name: untrusted(item.name), item_id: nil, deferred: true }
        end
      end
      private_class_method :accept_one
    end
  end
end
