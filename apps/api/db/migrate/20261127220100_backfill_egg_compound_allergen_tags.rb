# frozen_string_literal: true

# WBW-244: egg noodles, egg pasta, and wonton wrappers now derive
# contains-egg via TagDeriver::SLUG_TAGS. Dishes that already carry
# those ingredients still have no egg tag, so an egg-avoider sees them
# as safe. Add the missing tag as ingredient_derived / suggested — the
# same write SauceAllergenBackfill makes for aioli — and never replace a
# tag already on the dish (Laan Thai's hand-added contains-egg stays).
#
# Drafts are included: a later status-only publish does not re-derive
# allergens, so a draft left untagged would go live still missing egg.
#
# Idempotent: a second `up` finds no dish that still lacks the tag.
# `down` does not strip it — that is the unsafe direction.
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
      WHERE ingredient_ids && ARRAY[#{quoted_ids(compound_ids)}]::uuid[]
        AND NOT (COALESCE(tag_ids, '{}'::uuid[]) && ARRAY[#{connection.quote(egg_tag_id)}]::uuid[])
    SQL
    return if item_ids.empty?

    say_with_time "add contains-egg to #{item_ids.size} egg-compound dish(es)" do
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

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(", ")
  end
end
