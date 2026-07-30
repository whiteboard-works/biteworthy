class AddEnrichmentStatusToIngestionRuns < ActiveRecord::Migration[8.1]
  # Deterministic-resolve rework: the run reaches :staged as soon as the
  # code-side resolver finishes, while the LLM gap-fill pass may still be
  # enriching pending items in the background. Clients read this column to
  # know whether to keep polling for late-arriving suggestions.
  # Values: pending | completed | failed.
  def change
    add_column :ingestion_runs, :enrichment_status, :string, null: false, default: "pending"
  end
end
