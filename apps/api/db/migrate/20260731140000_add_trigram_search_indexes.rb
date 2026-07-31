class AddTrigramSearchIndexes < ActiveRecord::Migration[8.1]
  # Both searches are `ILIKE '%q%'`, which no btree index can serve —
  # `restaurants.name` backs the public city search, `tags.name` the
  # admin taxonomy picker. `items.name` and `ingredients.name` already
  # carry this index; these two were missed.
  #
  # Deliberately NOT indexing users.email/handle/display_name: that
  # search is admin-only over a table that stays small, and three more
  # GIN indexes would tax every user write to speed up a page a handful
  # of people open.
  disable_ddl_transaction!

  def change
    add_index :restaurants, :name, using: :gin, opclass: :gin_trgm_ops,
              algorithm: :concurrently
    add_index :tags, :name, using: :gin, opclass: :gin_trgm_ops,
              algorithm: :concurrently
  end
end
