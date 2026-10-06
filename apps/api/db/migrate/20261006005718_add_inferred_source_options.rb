# frozen_string_literal: true

# Add new source values for ingredient/tag joins to support the confidence model:
# - "match": deterministic resolver found an exact taxonomy match
# - "derived": ingredient name/keyword inference (e.g., pizza → wheat)
# - "ingredient_derived": allergen tag inferred from an ingredient
#
# This migration uses NOT VALID + VALIDATE CONSTRAINT to avoid a full table lock.
class AddInferredSourceOptions < ActiveRecord::Migration[8.1]
  def up
    # Drop the existing check constraints
    execute <<~SQL.squish
      ALTER TABLE item_ingredients
      DROP CONSTRAINT IF EXISTS item_ingredients_source_valid
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_tags
      DROP CONSTRAINT IF EXISTS item_tags_source_valid
    SQL

    # Add the new constraints with the expanded source values
    # Using NOT VALID to avoid locking, then VALIDATE immediately (safe on small tables)
    execute <<~SQL.squish
      ALTER TABLE item_ingredients
      ADD CONSTRAINT item_ingredients_source_valid
      CHECK (source IN ('human', 'ai', 'owner', 'match', 'derived', 'ingredient_derived'))
      NOT VALID
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_ingredients
      VALIDATE CONSTRAINT item_ingredients_source_valid
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_tags
      ADD CONSTRAINT item_tags_source_valid
      CHECK (source IN ('human', 'ai', 'owner', 'match', 'derived', 'ingredient_derived'))
      NOT VALID
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_tags
      VALIDATE CONSTRAINT item_tags_source_valid
    SQL
  end

  def down
    # Revert to the original constraints
    execute <<~SQL.squish
      ALTER TABLE item_ingredients
      DROP CONSTRAINT IF EXISTS item_ingredients_source_valid
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_tags
      DROP CONSTRAINT IF EXISTS item_tags_source_valid
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_ingredients
      ADD CONSTRAINT item_ingredients_source_valid
      CHECK (source IN ('human', 'ai', 'owner'))
    SQL

    execute <<~SQL.squish
      ALTER TABLE item_tags
      ADD CONSTRAINT item_tags_source_valid
      CHECK (source IN ('human', 'ai', 'owner'))
    SQL
  end
end
