# frozen_string_literal: true

# 20261013010000 moves the hard-soda aliases onto `alcohol.beer` so a
# future IngredientMatcher run hides those dishes from a celiac preset.
# It does not touch live joins. Dishes accepted while the aliases sat on
# the `alcohol` root still have an ItemIngredient pointing there, and
# avoiding `alcohol.beer` does not expand up to the parent — those
# dishes stay visible. This rewrite is the live-row half of that move.
#
# Scoped to the three moved phrases in the dish name or description, and
# to joins that currently point at the alcohol root. Curator (`human` /
# `owner`) rows are left alone unless the dish *name* itself is one of
# those phrases — then the join is the hard soda, even if a person
# confirmed the matcher's alcohol node. A wine a curator tagged alcohol
# whose description happens to mention a hard soda is not rewritten.
#
# Idempotent: a second `up` finds no remaining alcohol-root joins on
# those dishes. `down` does not put them back — that is the unsafe
# direction.
class RewriteHardSodaItemIngredientsToBeer < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  # Keep in lockstep with MoveHardSodaAliasesToBeer::MOVED.
  MOVED = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze

  def up
    alcohol_id = MigrationIngredient.where(slug: "alcohol").pick(:id)
    beer_id    = MigrationIngredient.where(slug: "alcohol-beer").pick(:id)
    unless alcohol_id && beer_id && alcohol_id != beer_id
      say "Taxonomy not seeded; skipping hard-soda join rewrite"
      return
    end

    item_ids = connection.select_values(<<~SQL.squish)
      SELECT DISTINCT e.item_id FROM (#{eligible_joins_sql(alcohol_id)}) e
    SQL
    return if item_ids.empty?

    say_with_time "rewrite #{item_ids.size} hard-soda dish(es) off the alcohol root" do
      drop_duplicate_alcohol_joins(alcohol_id, beer_id)
      point_remaining_joins_at_beer(alcohol_id, beer_id)
      resync_ingredient_ids(item_ids)
    end
  end

  def down
    # Non-destructive. Restoring the alcohol-root joins would re-open the
    # celiac under-hide this exists to close.
  end

  private

  # Alcohol-root joins on a dish whose name or description contains a
  # moved alias. Matcher/AI/derived rows always qualify; curator rows
  # only when the name itself carries the phrase.
  def eligible_joins_sql(alcohol_id)
    haystack   = "lower(coalesce(i.name, '') || ' ' || coalesce(i.description, ''))"
    name_hay   = "lower(coalesce(i.name, ''))"
    any_phrase = or_phrases(haystack)
    name_phrase = or_phrases(name_hay)

    <<~SQL.squish
      SELECT ii.id, ii.item_id
      FROM item_ingredients ii
      INNER JOIN items i ON i.id = ii.item_id
      WHERE ii.ingredient_id = #{connection.quote(alcohol_id)}
        AND (#{any_phrase})
        AND (
          ii.source NOT IN ('human', 'owner')
          OR (#{name_phrase})
        )
    SQL
  end

  def or_phrases(haystack)
    MOVED.map { |phrase| "position(#{connection.quote(phrase)} in #{haystack}) > 0" }.join(" OR ")
  end

  def drop_duplicate_alcohol_joins(alcohol_id, beer_id)
    execute(<<~SQL.squish)
      DELETE FROM item_ingredients ii
      WHERE ii.id IN (
        SELECT e.id FROM (#{eligible_joins_sql(alcohol_id)}) e
        WHERE EXISTS (
          SELECT 1 FROM item_ingredients beer
          WHERE beer.item_id = e.item_id
            AND beer.ingredient_id = #{connection.quote(beer_id)}
        )
      )
    SQL
  end

  def point_remaining_joins_at_beer(alcohol_id, beer_id)
    execute(<<~SQL.squish)
      UPDATE item_ingredients ii
      SET ingredient_id = #{connection.quote(beer_id)}, updated_at = CURRENT_TIMESTAMP
      FROM (#{eligible_joins_sql(alcohol_id)}) e
      WHERE ii.id = e.id
    SQL
  end

  # Recompute from the join table — the same statement SyncsDenormalizedIds
  # uses. A direct write of the old array minus alcohol plus beer would
  # drift if another join changed in the same window.
  def resync_ingredient_ids(item_ids)
    execute(<<~SQL.squish)
      UPDATE items
      SET ingredient_ids = (
        SELECT COALESCE(array_agg(j.ingredient_id), '{}'::uuid[])
        FROM item_ingredients j
        WHERE j.item_id = items.id
      ), updated_at = CURRENT_TIMESTAMP
      WHERE id IN (#{item_ids.map { |id| connection.quote(id) }.join(", ")})
    SQL
  end
end
