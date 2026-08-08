# Stage one of the ingestion pipeline, run in the background because the
# vision call legitimately takes tens of seconds — far too long to block an
# MCP tool call or a chat turn.
#
# The logic lives in Ingestion::ExtractRun; this is the async wrapper.
# Dispatch is explicit at the call site (Ingestion::StartRun and
# Ingestion::ReExtractRun) rather than hidden in a model state callback.
class ExtractMenuJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    Ingestion::ExtractRun.call(IngestionRun.find(ingestion_run_id))
  end
end
