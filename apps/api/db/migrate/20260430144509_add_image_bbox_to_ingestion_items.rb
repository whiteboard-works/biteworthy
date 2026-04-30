class AddImageBboxToIngestionItems < ActiveRecord::Migration[8.1]
  # Phase 4.11.1 — when Anthropic vision identifies a per-dish photo
  # on the source page, it returns the bounding box as
  # `{x, y, w, h}` in normalized coordinates (0..1, fractions of the
  # source page). Storing as jsonb lets us evolve the schema (e.g.
  # add `confidence`) without another migration.
  #
  # Nullable: many menu items don't have an associated photo. Items
  # without a bbox just don't get a cropped photo on promote.
  def change
    add_column :ingestion_items, :image_bbox, :jsonb
  end
end
