class AddExtractionFieldsToIngestionRuns < ActiveRecord::Migration[8.1]
  # Phase 2.3 columns:
  # - `staging` is the parsed/validated extraction (the structured
  #   JSON that ResolveIngredientsJob in 2.4 will read).
  # - `raw_output` (already on the table) keeps the full Anthropic
  #   API response for debugging.
  #
  # Phase 2.9 (cost dashboard) columns:
  # - `api_cost_cents` accumulates across the run's stages.
  # - `latency_ms` is the wall time of the last API call.
  # - `cached_input_tokens` / `uncached_input_tokens` let us track
  #   prompt-cache hit rate over time.
  def change
    add_column :ingestion_runs, :staging,               :jsonb,   default: {}, null: false
    add_column :ingestion_runs, :api_cost_cents,        :integer, default: 0,  null: false
    add_column :ingestion_runs, :latency_ms,            :integer
    add_column :ingestion_runs, :cached_input_tokens,   :integer, default: 0,  null: false
    add_column :ingestion_runs, :uncached_input_tokens, :integer, default: 0,  null: false
  end
end
