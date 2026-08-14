class DropPopularityFromItems < ActiveRecord::Migration[8.1]
  # `items.popularity` was read in three places and written by none.
  #
  # It ordered the menu (`popularity DESC, name ASC`), carried a 0.5 weight
  # in `TasteScoring`, and rode along in the item payload — but nothing in
  # the app has ever set it: no job, no ingestion path, and not even the
  # admin item editor, whose `permit` list leaves it out. Every row is 0,
  # so the scoring term is structurally zero (`popularity / NULLIF(max, 0)`
  # is `NULL` when the max is 0, coalesced to 0) and the "order" it
  # provided is really `name ASC`.
  #
  # The choice was to wire a writer or drop the column; dropped, because a
  # popularity signal we are not collecting cannot be recovered by keeping
  # an empty column for it, and a weight that reads as tuned-and-considered
  # while contributing nothing is worse than its absence. `restaurant_visits`
  # and `favorite_items` are still the obvious inputs if it comes back.
  #
  # Irreversible on purpose rather than by omission: `up` throws away data,
  # and a `down` that restores the column would restore it full of zeros,
  # which is indistinguishable from the real thing and would quietly re-arm
  # the same illusion. Rolling this back means restoring from a backup.
  def up
    remove_column :items, :popularity
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "popularity held no data worth restoring; recreate it with a writer if it comes back"
  end
end
