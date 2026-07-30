class AddEnrichmentStatusToIngestionRuns < ActiveRecord::Migration[8.1]
  # Deterministic-resolve rework: the run reaches :staged as soon as the
  # code-side resolver finishes, while the LLM gap-fill pass may still be
  # enriching pending items in the background. Clients read this column to
  # know whether to keep polling for late-arriving suggestions.
  # Values: pending | completed | failed.
  def up
    add_column :ingestion_runs, :enrichment_status, :string, null: false, default: "pending"

    # Backfill settled pre-rework runs: no gap-fill job will ever run for
    # them, so a "pending" default would make their verify pages poll
    # forever. In-flight runs (queued/extracting/resolving) get the column
    # written by ResolveItemsJob when they land.
    execute <<~SQL
      UPDATE ingestion_runs
      SET enrichment_status = 'completed'
      WHERE status IN ('staged', 'published', 'failed')
    SQL
  end

  def down
    remove_column :ingestion_runs, :enrichment_status
  end
end
