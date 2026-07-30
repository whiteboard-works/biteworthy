class Avo::Actions::IngestionRuns::ReExtract < Avo::BaseAction
  self.name = "Re-run extraction"
  self.message = "Reset this run to :extracting and fire ExtractMenuJob again? Useful when the original extraction returned bad output (the cassette didn't match a valid menu shape, or the model returned weirdness)."
  self.confirm_button_label = "Re-extract"

  # Logic lives in Ingestion::ReExtractRun (shared with the admin API).
  def handle(query:, **)
    skipped = 0
    query.each do |run|
      Ingestion::ReExtractRun.call(run)
    rescue Ingestion::ReExtractRun::AlreadyPublished,
           Ingestion::ReExtractRun::HasPromotedItems
      skipped += 1 # Live data — don't blow it up from a bulk action
    end

    msg = +"Re-extraction enqueued for #{query.size - skipped} run(s)."
    msg << " Skipped #{skipped} with live items." if skipped.positive?
    succeed msg
  end
end
