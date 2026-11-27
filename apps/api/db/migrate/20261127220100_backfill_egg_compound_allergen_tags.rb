# frozen_string_literal: true

# WBW-244: egg noodles, egg pasta, and wonton wrappers now derive
# contains-egg via TagDeriver::SLUG_TAGS. Dishes already published with
# those ingredients still have no egg tag, so an egg-avoider sees them
# as safe. Add the missing tag as ingredient_derived / suggested — the
# same write SauceAllergenBackfill makes for aioli — and never replace a
# tag already on the dish (Laan Thai's hand-added contains-egg stays).
#
# Idempotent: a second `up` finds no published dish that still lacks the
# tag. `down` does not strip it — that is the unsafe direction.
class BackfillEggCompoundAllergenTags < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class MigrationTag < ActiveRecord::Base
    self.table_name = "tags"
  end

  COMPOUND_SLUGS = %w[
    grain-wheat-noodle-egg
    grain-wheat-pasta-egg
    grain-wheat-wonton
  ].freeze
  EGG_TAG_SLUG = "contains-egg"

  def up
    egg_tag_id = MigrationTag.where(slug: EGG_TAG_SLUG).pick(:id)
    compound_ids = MigrationIngredient.where(slug: COMPOUND_SLUGS).pluck(:id)
    if egg_tag_id.blank? || compound_ids.empty?
      say "Taxonomy not seeded; skipping egg-compound allergen backfill"
      return
    end

    item_ids = connection.select_values(<<~SQL.squish)
      SELECT id FROM items
      WHERE status = 'published'
        AND ingredient_ids && ARRAY[#{quoted_ids(compound_ids)}]::uuid[]
        AND NOT (COALESCE(tag_ids, '{}'::uuid[]) && ARRAY[#{connection.quote(egg_tag_id)}]::uuid[])
    SQL
    return if item_ids.empty?

    say_with_time "add contains-egg to #{item_ids.size} published egg-compound dish(es)" do
      execute(<<~SQL.squish)
        INSERT INTO item_tags (id, item_id, tag_id, confidence, source, created_at, updated_at)
        SELECT gen_random_uuid(), items.id, #{connection.quote(egg_tag_id)},
               'suggested', 'ingredient_derived', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM items
        WHERE items.id IN (#{quoted_ids(item_ids)})
          AND NOT EXISTS (
            SELECT 1 FROM item_tags existing
            WHERE existing.item_id = items.id
              AND existing.tag_id = #{connection.quote(egg_tag_id)}
          )
      SQL
      resync_tag_ids(item_ids)
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

  def resync_tag_ids(item_ids)
    execute(<<~SQL.squish)
      UPDATE items
      SET tag_ids = (
        SELECT COALESCE(array_agg(j.tag_id), '{}'::uuid[])
        FROM item_tags j
        WHERE j.item_id = items.id
      ), updated_at = CURRENT_TIMESTAMP
      WHERE id IN (#{quoted_ids(item_ids)})
    SQL
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(", ")
  end
end
