class Avo::Actions::IngestionRuns::ReExtract < Avo::BaseAction
  self.name = "Re-run extraction"
  self.message = "Reset this run to :extracting and fire ExtractMenuJob again? Useful when the original extraction returned bad output (the cassette didn't match a valid menu shape, or the model returned weirdness)."
  self.confirm_button_label = "Re-extract"

  def handle(query:, **)
    query.each do |run|
      next if run.published? # Don't blow up an already-published run

      run.update!(staging: {}, failure_message: nil, latency_ms: nil,
                  state_history: run.state_history.except("extracting", "resolving", "staged", "failed"))
      # Force back to :queued via direct write (transition_to! enforces
      # forward-only chains and we're rewinding).
      run.update_columns(status: "queued")
      ExtractMenuJob.perform_later(run.id)
    end

    succeed "Re-extraction enqueued for #{query.size} run(s)."
  end
end
