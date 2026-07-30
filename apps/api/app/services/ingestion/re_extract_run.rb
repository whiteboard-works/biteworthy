# frozen_string_literal: true

# Rewinds a run to :queued and re-fires ExtractMenuJob — for when the
# original extraction returned bad output (invalid menu shape, model
# weirdness). Extracted from the Avo re-extract action so the admin
# API and Avo share one implementation (and retiring Avo removes no
# logic). Published runs are refused: their items are already live.
module Ingestion
  class ReExtractRun
    class AlreadyPublished < StandardError; end

    def self.call(run)
      raise AlreadyPublished, "run #{run.id} is published" if run.published?

      run.update!(
        staging:         {},
        failure_message: nil,
        latency_ms:      nil,
        state_history:   run.state_history.except("extracting", "resolving", "staged", "failed")
      )
      # Rewind to :queued via direct write — transition_to! enforces
      # forward-only chains and this is deliberately a rewind.
      run.update_columns(status: "queued")
      ExtractMenuJob.perform_later(run.id)
      run
    end
  end
end
