# Stage two of the ingestion pipeline. Deterministic and fast, but kept as
# a job so extraction can hand off without blocking on it.
#
# The logic lives in Ingestion::ResolveRun; this is the async wrapper.
# Enqueued explicitly by Ingestion::ExtractRun.
class ResolveItemsJob < ApplicationJob
  queue_as :ingestion

  def perform(ingestion_run_id)
    Ingestion::ResolveRun.call(IngestionRun.find(ingestion_run_id))
  end
end
