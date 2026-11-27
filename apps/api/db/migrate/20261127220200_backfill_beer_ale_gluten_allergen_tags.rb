# frozen_string_literal: true

# WBW-245: beer/ale (and beer-style children: IPA, lager, pilsner, …)
# now derive contains-gluten via TagDeriver::SUBTREE_TAGS. Dishes that
# already join those nodes still have no gluten tag, so a user who
# avoids the tag without also avoiding the ingredient still sees them
# as safe. Same write as the egg-compound backfill: suggested /
# ingredient_derived, never replace a tag already on the dish.
#
# Hard seltzer is alcohol.seltzer, outside these prefixes.
#
# Idempotent. `down` does not strip the tag.
class BackfillBeerAleGlutenAllergenTags < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class MigrationTag < ActiveRecord::Base
    self.table_name = "tags"
  end

  GLUTEN_TAG_SLUG = "contains-gluten"
  BEER_ALE_PATHS = [ "alcohol.beer", "alcohol.ale" ].freeze

  def up
    gluten_tag_id = MigrationTag.where(slug: GLUTEN_TAG_SLUG).pick(:id)
    beer_ids = beer_ale_ingredient_ids
    if gluten_tag_id.blank? || beer_ids.empty?
      say "Taxonomy not seeded; skipping beer/ale gluten allergen backfill"
      return
    end

    item_ids = connection.select_values(<<~SQL.squish)
      SELECT id FROM items
      WHERE ingredient_ids && ARRAY[#{quoted_ids(beer_ids)}]::uuid[]
        AND NOT (COALESCE(tag_ids, '{}'::uuid[]) && ARRAY[#{connection.quote(gluten_tag_id)}]::uuid[])
    SQL
    return if item_ids.empty?

    say_with_time "add contains-gluten to #{item_ids.size} beer/ale dish(es)" do
      execute(<<~SQL.squish)
        INSERT INTO item_tags (id, item_id, tag_id, confidence, source, created_at, updated_at)
        SELECT gen_random_uuid(), items.id, #{connection.quote(gluten_tag_id)},
               'suggested', 'ingredient_derived', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM items
        WHERE items.id IN (#{quoted_ids(item_ids)})
          AND NOT EXISTS (
            SELECT 1 FROM item_tags existing
            WHERE existing.item_id = items.id
              AND existing.tag_id = #{connection.quote(gluten_tag_id)}
          )
      SQL
      ItemTag.resync_denormalized_ids(item_ids)
      execute(<<~SQL.squish)
        UPDATE items
        SET confidence = 'suggested', updated_at = CURRENT_TIMESTAMP
        WHERE id IN (#{quoted_ids(item_ids)})
          AND confidence = 'confirmed'
      SQL
    end
  end

  def down
    # Non-destructive. Removing the tags would re-open the under-hide.
  end

  private

  def beer_ale_ingredient_ids
    clauses = BEER_ALE_PATHS.map { |path| "path <@ #{connection.quote(path)}::ltree" }.join(" OR ")
    MigrationIngredient.where(clauses).pluck(:id)
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(", ")
  end
end
