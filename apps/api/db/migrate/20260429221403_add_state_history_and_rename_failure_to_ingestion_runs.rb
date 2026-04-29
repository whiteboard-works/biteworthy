class AddStateHistoryAndRenameFailureToIngestionRuns < ActiveRecord::Migration[8.1]
  # Phase 2.2 wires up the IngestionRun state machine.
  #
  # `state_history` is an audit trail keyed by state name with the UTC
  # timestamp of when the run entered that state — set once per state
  # so repeated transition_to! calls don't overwrite the original
  # entry timestamp. Used by the cost dashboard (Phase 2.9) to compute
  # per-stage latency.
  #
  # `error_message` → `failure_message` aligns the column name with
  # phase-2.md and with how the rest of the pipeline talks about
  # failed runs ("the run's failure_message").
  def change
    add_column :ingestion_runs, :state_history, :jsonb, default: {}, null: false
    rename_column :ingestion_runs, :error_message, :failure_message
  end
end
