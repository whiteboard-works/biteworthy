# frozen_string_literal: true

module Tools
  module Ingestion
    class GetScanStatus < Tools::Ingestion::Base
      tool_name "get_scan_status"
      title "Check a menu scan"
      description <<~TEXT
        Where a menu scan has got to. Poll this after `start_menu_scan`.

        `ready: true` means the dishes are staged and you can call
        `list_staged_items`. Until then, wait a few seconds and poll again —
        extraction usually takes 20-60 seconds. Tell the user it's running
        rather than silently looping.

        `failed: true` means the scan failed; `failure_message` says why and
        the scan cannot be resumed — start a new one.

        `enrichment_status: "pending"` means a background pass is still
        adding ingredient suggestions to dishes the deterministic matcher
        couldn't resolve. The dishes are usable and reviewable meanwhile;
        those specific ones may gain ingredients shortly.
      TEXT

      input_schema(
        properties: {
          scan_id: { type: "string", description: "The scan id returned by start_menu_scan." }
        },
        required: ["scan_id"]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Checking on the scan" }

      def self.perform(context:, scan_id:)
        run = find_run!(context, scan_id)

        ok(
          scan_id:           run.id,
          status:            run.status,
          ready:             run.staged? || run.published?,
          failed:            run.failed?,
          failure_message:   run.failure_message,
          enrichment_status: run.enrichment_status,
          restaurant_id:     run.restaurant_id,
          dish_count:        run.ingestion_items.count,
          pending_count:     run.ingestion_items.where(decision: "pending").count,
          accepted_count:    run.ingestion_items.where(decision: "accepted").count,
          rejected_count:    run.ingestion_items.where(decision: "rejected").count
        )
      end
    end
  end
end
