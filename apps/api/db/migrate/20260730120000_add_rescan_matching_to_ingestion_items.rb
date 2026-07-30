class AddRescanMatchingToIngestionItems < ActiveRecord::Migration[8.1]
  # Re-scan dedup: ResolveItemsJob matches staged items against the
  # restaurant's existing Items (Ingestion::ExistingItemMatcher) and links
  # the candidate here. nullify-on-delete is the fallback semantics — if
  # the matched Item disappears before the human accepts, the link
  # self-clears and accept falls back to creating a fresh Item.
  def change
    add_column :ingestion_items, :matched_item_id, :uuid
    add_column :ingestion_items, :match_score, :float
    add_index  :ingestion_items, :matched_item_id
    add_foreign_key :ingestion_items, :items, column: :matched_item_id, on_delete: :nullify
  end
end
