class AddCreatedAtIndexToIngestionRuns < ActiveRecord::Migration[8.1]
  # Ingestion::StartRun#todays_spend_cents sums api_cost_cents over every run
  # created today, and it runs twice per scan — the second time inside the
  # per-user advisory lock. ingestion_runs carried indexes only on
  # restaurant_id and user_id, so that sum was a sequential scan of the whole
  # table with every concurrent scanner queued behind it, growing with total
  # scans ever taken rather than with today's.
  disable_ddl_transaction!

  def change
    add_index :ingestion_runs, :created_at, algorithm: :concurrently
  end
end
