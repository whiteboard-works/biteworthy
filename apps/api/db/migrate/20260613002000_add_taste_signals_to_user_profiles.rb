# Phase 8.1 — taste signals. Soft preferences that RANK the safe
# items (Top Picks); they never hide anything — that's what the avoid
# arrays are for. Read-side only in the ranking query (no membership
# lookups against these from other rows), so no GIN indexes.
class AddTasteSignalsToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :user_profiles, :liked_ingredient_ids,    :uuid, array: true, default: [], null: false
    add_column :user_profiles, :liked_tag_ids,           :uuid, array: true, default: [], null: false
    add_column :user_profiles, :disliked_ingredient_ids, :uuid, array: true, default: [], null: false
    add_column :user_profiles, :disliked_tag_ids,        :uuid, array: true, default: [], null: false
  end
end
