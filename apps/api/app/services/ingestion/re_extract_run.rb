# frozen_string_literal: true

# Rewinds a run to :queued and re-fires ExtractMenuJob — for when the
# original extraction returned bad output (invalid menu shape, model
# weirdness). Extracted from the Avo re-extract action so the admin
# API and Avo share one implementation (and retiring Avo removes no
# logic).
#
# Two refusals, both about live data:
#   - published runs: the whole item set is live;
#   - any run with a promoted item (item_id present) — re-extraction
#     would orphan the live Item from its staged row. Undo the accepts
#     first if a rewind is really wanted.
# Un-promoted staged rows are cleared in the same transaction —
# ExtractMenuJob materializes a fresh set, and leaving the old one
# would double every card in the verify deck.
#
# Known narrow race: rewinding while the original ExtractMenuJob is
# mid-flight lets the stale job finish from its in-memory state, after
# which the re-fired job's state guard turns this rewind into a no-op
# (and both API calls bill). Admin-only, self-healing, accepted.
module Ingestion
  class ReExtractRun
    class AlreadyPublished < StandardError; end
    class HasPromotedItems < StandardError; end

    def self.call(run)
      raise AlreadyPublished, "run #{run.id} is published" if run.published?

      run.transaction do
        if run.ingestion_items.where.not(item_id: nil).exists?
          raise HasPromotedItems, "run #{run.id} has promoted items"
        end

        run.ingestion_items.delete_all
        run.update!(
          staging:         {},
          failure_message: nil,
          latency_ms:      nil,
          state_history:   run.state_history.except("extracting", "resolving", "staged", "failed")
        )
        # Rewind to :queued via direct write — transition_to! enforces
        # forward-only chains and this is deliberately a rewind.
        run.update_columns(status: "queued")
      end
      ExtractMenuJob.perform_later(run.id)
      run
    end
  end
end
