class AddUnresolvedTagsToIngestionItems < ActiveRecord::Migration[8.1]
  # Mirrors `unresolved_ingredients` (already on the table) — the
  # raw tag strings the AI extracted that didn't match the catalog,
  # surfaced in the swipe-verify UI for human curation.
  def change
    add_column :ingestion_items, :unresolved_tags, :jsonb, default: [], null: false
  end
end
