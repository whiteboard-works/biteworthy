class DropPopularityFromItems < ActiveRecord::Migration[8.1]
  # Step two of dropping `items.popularity`. Step one had to be live on
  # the box first, and was: #601 deployed 2026-08-14 18:16 UTC, verified
  # by the menu endpoint answering without the field.
  #
  # A read-only production audit ran before this merged, because "no
  # writer in the code" does not establish "no data in the table" for an
  # irreversible drop. All 89 rows held 0, no NULLs, max 0 — so this
  # discards nothing.
  #
  # Step one (#601) removed every reader — the `TasteScoring` weight, the
  # menu's `popularity DESC` ordering, the Top Picks tie-break, the field
  # in the item payload — and declared the column in `Item.ignored_columns`.
  # This is only safe once that release is serving traffic, because
  # `bin/docker-entrypoint` runs `db:prepare` when the new puma container
  # boots while kamal-proxy is still routing to the old one: drop a column
  # the running release reads and every menu request in the deploy window
  # raises `PG::UndefinedColumn`.
  #
  # The column had no writer — not a job, not ingestion, and not the admin
  # item editor, whose `permit` list leaves it out — so the scoring term it
  # fed was structurally zero and the "order" it provided was `name ASC`.
  # It is dropped rather than wired because a popularity signal we are not
  # collecting is not recovered by keeping an empty column for it;
  # `restaurant_visits` and `favorite_items` are the obvious inputs if one
  # is wanted later.
  #
  # Irreversible on purpose rather than by omission: `up` throws data away,
  # and a `down` that recreated the column would fill it with zeros —
  # indistinguishable from the real thing, and enough to re-arm the same
  # illusion of a tuned weight that contributes nothing.
  def up
    remove_column :items, :popularity
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "popularity held no data worth restoring; recreate it with a writer if it comes back"
  end
end
