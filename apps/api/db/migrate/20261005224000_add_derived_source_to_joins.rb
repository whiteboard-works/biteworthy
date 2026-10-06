# frozen_string_literal: true

class AddDerivedSourceToJoins < ActiveRecord::Migration[8.0]
  def up
    # Add 'derived' to the allowed source values for item_ingredients and item_tags
    # (deterministic resolver uses this for implied-base keywords like wheat in "pizza")
    execute <<~SQL.squish
      ALTER TABLE item_ingredients DROP CONSTRAINT IF EXISTS item_ingredients_source_valid;
      ALTER TABLE item_ingredients ADD CONSTRAINT item_ingredients_source_valid
        CHECK (source IN ('human', 'ai', 'owner', 'derived'));

      ALTER TABLE item_tags DROP CONSTRAINT IF EXISTS item_tags_source_valid;
      ALTER TABLE item_tags ADD CONSTRAINT item_tags_source_valid
        CHECK (source IN ('human', 'ai', 'owner', 'derived'));
    SQL
  end

  def down
    # Revert any 'derived' rows to 'human' before removing from enum
    execute <<~SQL.squish
      UPDATE item_ingredients SET source = 'human' WHERE source = 'derived';
      UPDATE item_tags SET source = 'human' WHERE source = 'derived';

      ALTER TABLE item_ingredients DROP CONSTRAINT IF EXISTS item_ingredients_source_valid;
      ALTER TABLE item_ingredients ADD CONSTRAINT item_ingredients_source_valid
        CHECK (source IN ('human', 'ai', 'owner'));

      ALTER TABLE item_tags DROP CONSTRAINT IF EXISTS item_tags_source_valid;
      ALTER TABLE item_tags ADD CONSTRAINT item_tags_source_valid
        CHECK (source IN ('human', 'ai', 'owner'));
    SQL
  end
end
