class AddAppliedChangesToIngestionItems < ActiveRecord::Migration[8.1]
  # Undo snapshot for update-accepts (re-scan flow): the exact fields
  # apply_update! changed on the matched Item — prior description /
  # confidence, replaced variant rows, created join ids — so undo can
  # restore them instead of destroying a pre-existing live Item.
  def change
    add_column :ingestion_items, :applied_changes, :jsonb
  end
end
