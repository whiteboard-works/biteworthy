class Avo::Actions::IngestionRuns::ReExtract < Avo::BaseAction
  self.name = "Re-run extraction"
  self.message = "Reset this run to :extracting and fire ExtractMenuJob again? Useful when the original extraction returned bad output (the cassette didn't match a valid menu shape, or the model returned weirdness)."
  self.confirm_button_label = "Re-extract"

  # Logic lives in Ingestion::ReExtractRun (shared with the admin API).
  def handle(query:, **)
    skipped = 0
    query.each do |run|
      Ingestion::ReExtractRun.call(run)
    rescue Ingestion::ReExtractRun::AlreadyPublished
      skipped += 1 # Don't blow up an already-published run
    end

    msg = +"Re-extraction enqueued for #{query.size - skipped} run(s)."
    msg << " Skipped #{skipped} published." if skipped.positive?
    succeed msg
  end
end
