# frozen_string_literal: true

class AddEnrichmentFailureMessageToIngestionRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :ingestion_runs, :enrichment_failure_message, :text
  end
end
