class AddArchivedAtToRestaurantsAndIngestionRuns < ActiveRecord::Migration[8.1]
  # Admin delete is soft by default, and these are the only two tables
  # without a tombstone of their own. Items use `status: "removed"`,
  # reviews `hidden_at`, suggestions `status: "rejected"` — reusing those
  # beats forking a second convention across five more tables.
  #
  # No index on either column. The read that matters is
  # `Restaurant.published`, which already filters on `status`, and an
  # archived row is by construction the rare one — a partial index would
  # cover the query nobody runs (find the archived ones) and not the one
  # that runs constantly.
  def change
    add_column :restaurants,    :archived_at, :datetime
    add_column :ingestion_runs, :archived_at, :datetime
  end
end
