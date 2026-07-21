class AddPositionToIngestionItems < ActiveRecord::Migration[8.1]
  # Flat index of the item within its run's extraction order. Set when
  # ExtractMenuJob materializes items up front (verify-flow redesign) so the
  # resolve stages can write their indexed results back onto the right item.
  # Nullable: rows from runs materialized the old way (at resolve-end) stay null.
  def change
    add_column :ingestion_items, :position, :integer
  end
end
