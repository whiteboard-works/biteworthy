# frozen_string_literal: true

# 20261013010000 moves the hard-soda aliases onto `alcohol.beer` so a
# future IngredientMatcher run hides those dishes from a celiac preset.
# It does not touch live joins or staged payloads. Dishes accepted (or
# staged) while the aliases sat on the `alcohol` root still point there,
# and avoiding `alcohol.beer` does not expand up to the parent — those
# dishes stay visible. This rewrite is the live-row half of that move.
#
# Scoped to the three moved phrases after the same normalization the
# matcher uses (hyphens, slashes, extra spaces), and to joins / staged
# payloads that currently name the alcohol root. Curator (`human` /
# `owner`) rows are left alone unless the dish *name* itself is one of
# those phrases. A wine a curator tagged alcohol whose description
# happens to mention a hard soda is not rewritten.
#
# Pending/edited IngestionItems have no ItemIngredient yet; promote!
# writes whatever slug is still in ingredients_payload, so those
# payloads are rewritten too.
#
# Idempotent: a second `up` finds no remaining alcohol-root joins or
# staged alcohol slugs on those dishes. `down` does not put them back —
# that is the unsafe direction.
class RewriteHardSodaItemIngredientsToBeer < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class MigrationIngestionItem < ActiveRecord::Base
    self.table_name = "ingestion_items"
  end

  # Keep in lockstep with MoveHardSodaAliasesToBeer::MOVED.
  MOVED = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze
  STAGED = %w[pending edited].freeze
  CURATOR = %w[human owner].freeze

  def up
    alcohol_id = MigrationIngredient.where(slug: "alcohol").pick(:id)
    beer_id    = MigrationIngredient.where(slug: "alcohol-beer").pick(:id)
    unless alcohol_id && beer_id && alcohol_id != beer_id
      say "Taxonomy not seeded; skipping hard-soda join rewrite"
      return
    end

    rewrite_joins(alcohol_id, beer_id)
    rewrite_staged_payloads
  end

  def down
    # Non-destructive. Restoring the alcohol-root joins would re-open the
    # celiac under-hide this exists to close.
  end

  private

  def rewrite_joins(alcohol_id, beer_id)
    rows = connection.select_all(<<~SQL.squish)
      SELECT ii.id, ii.item_id, ii.source, i.name, i.description
      FROM item_ingredients ii
      INNER JOIN items i ON i.id = ii.item_id
      WHERE ii.ingredient_id = #{connection.quote(alcohol_id)}
    SQL
    eligible = rows.select { |row| eligible_text?(row["name"], row["description"], source: row["source"]) }
    return if eligible.empty?

    item_ids = eligible.map { |row| row["item_id"] }.uniq
    join_ids = eligible.map { |row| row["id"] }

    say_with_time "rewrite #{item_ids.size} hard-soda dish(es) off the alcohol root" do
      drop_duplicate_alcohol_joins(join_ids, beer_id)
      point_remaining_joins_at_beer(join_ids, beer_id)
      resync_ingredient_ids(item_ids)
    end
  end

  def rewrite_staged_payloads
    rewritten = 0
    MigrationIngestionItem.where(decision: STAGED).find_each do |staged|
      next unless eligible_text?(staged.name, staged.description, source: "match")

      payload = Array(staged.ingredients_payload)
      updated = remap_payload(payload, name_has_phrase: phrase_in?(staged.name))
      next if updated == payload

      staged.update!(ingredients_payload: updated)
      rewritten += 1
    end
    say "rewrote #{rewritten} staged hard-soda payload(s)" if rewritten.positive?
  end

  # Matcher/AI/derived rows always qualify when the phrase is in name or
  # description; curator rows only when the name itself carries it.
  def eligible_text?(name, description, source:)
    return false unless phrase_in?("#{name} #{description}")
    return true unless CURATOR.include?(source.to_s)

    phrase_in?(name)
  end

  def phrase_in?(text)
    hay = normalize(text)
    MOVED.any? { |phrase| hay.include?(phrase) }
  end

  # Copied from Ingestion::MenuText.normalize so a later matcher change
  # cannot silently retarget an already-run data migration. Hyphens,
  # slashes, leftover punctuation, and extra whitespace have to fold the
  # same way they did when the join was written.
  def normalize(text)
    ActiveSupport::Inflector
      .transliterate(text.to_s.downcase)
      .gsub("&", " and ")
      .tr("-/", "  ")
      .gsub(/[^a-z0-9 ]/, " ")
      .squish
  end

  def remap_payload(payload, name_has_phrase:)
    rows = payload.map { |row| stringify_row(row) }
    has_beer = rows.any? { |row| row["slug"] == "alcohol-beer" }
    rows.filter_map do |row|
      next row unless row["slug"] == "alcohol"
      next row if CURATOR.include?(row["source"].to_s) && !name_has_phrase
      next if has_beer

      has_beer = true
      row.merge("slug" => "alcohol-beer")
    end
  end

  def stringify_row(row)
    row.respond_to?(:to_h) ? row.to_h.stringify_keys : { "slug" => row }
  end

  def drop_duplicate_alcohol_joins(join_ids, beer_id)
    execute(<<~SQL.squish)
      DELETE FROM item_ingredients ii
      WHERE ii.id IN (#{quoted_ids(join_ids)})
        AND EXISTS (
          SELECT 1 FROM item_ingredients beer
          WHERE beer.item_id = ii.item_id
            AND beer.ingredient_id = #{connection.quote(beer_id)}
        )
    SQL
  end

  def point_remaining_joins_at_beer(join_ids, beer_id)
    execute(<<~SQL.squish)
      UPDATE item_ingredients
      SET ingredient_id = #{connection.quote(beer_id)}, updated_at = CURRENT_TIMESTAMP
      WHERE id IN (#{quoted_ids(join_ids)})
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
      WHERE id IN (#{quoted_ids(item_ids)})
    SQL
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(", ")
  end
end
