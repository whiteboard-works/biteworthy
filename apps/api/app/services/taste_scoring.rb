# Phase 8.2 — the taste scoring engine (SQL side).
#
# score(item) =
#     2.0 * |item.tag_ids ∩ liked_tag_ids|
#   + 1.0 * |item.ingredient_ids ∩ liked_ingredient_ids|
#   - 2.0 * |item.tag_ids ∩ disliked_tag_ids|
#   - 1.0 * |item.ingredient_ids ∩ disliked_ingredient_ids|
#   + 0.5 * (avg_visible_rating - 3) / 2          (0 when unreviewed)
#
# There was a sixth term, `0.5 * popularity / max_popularity`, and it was
# always zero: nothing in the app ever wrote `items.popularity`, so the
# column was dropped rather than given a writer. If a popularity signal
# arrives later (`restaurant_visits` and `favorite_items` are the obvious
# sources) it comes back as a term here and a weight below.
#
# Safety filters, taste ranks: scores reorder and highlight, they
# never hide. This is the only implementation — clients render the
# `taste_score` / `taste_reasons` the items endpoint emits and never
# recompute them. `packages/filter-engine/fixtures/taste-parity.json`
# pins the arithmetic above, asserted to 4dp by
# `spec/services/taste_scoring_spec.rb`; change a weight or a term and
# the fixture has to move with it.
#
# Callers pass Signals that have already had the avoid lists
# subtracted (filter wins; an avoided id never scores) — see
# Menus::Filter#taste_signals_for.
class TasteScoring
  WEIGHTS = {
    liked_tag:           2.0,
    liked_ingredient:    1.0,
    disliked_tag:        2.0, # subtracted
    disliked_ingredient: 1.0, # subtracted
    rating:              0.5
  }.freeze

  Signals = Struct.new(
    :liked_ingredient_ids, :liked_tag_ids,
    :disliked_ingredient_ids, :disliked_tag_ids,
    keyword_init: true
  ) do
    def any?
      [liked_ingredient_ids, liked_tag_ids,
       disliked_ingredient_ids, disliked_tag_ids].any?(&:present?)
    end
  end

  # Every value reaches the SQL through a sanitize_sql_array
  # placeholder — weights included, so the score expression and the
  # WEIGHTS constant cannot drift apart.
  SCORES_SQL = <<~SQL.freeze
    SELECT scored.id,
           (? * cardinality(scored.matched_liked_tag_ids)
          + ? * cardinality(scored.matched_liked_ingredient_ids)
          - ? * scored.disliked_tag_count
          - ? * scored.disliked_ingredient_count
          + ? * COALESCE((scored.avg_rating - 3) / 2.0, 0)) AS score,
           scored.matched_liked_tag_ids,
           scored.matched_liked_ingredient_ids
    FROM (
      SELECT items.id,
             (SELECT COALESCE(array_agg(t ORDER BY t), '{}')
                FROM unnest(items.tag_ids) AS t
               WHERE t = ANY(CAST(? AS uuid[])))    AS matched_liked_tag_ids,
             (SELECT COALESCE(array_agg(i ORDER BY i), '{}')
                FROM unnest(items.ingredient_ids) AS i
               WHERE i = ANY(CAST(? AS uuid[])))    AS matched_liked_ingredient_ids,
             (SELECT COUNT(*)
                FROM unnest(items.tag_ids) AS t
               WHERE t = ANY(CAST(? AS uuid[])))    AS disliked_tag_count,
             (SELECT COUNT(*)
                FROM unnest(items.ingredient_ids) AS i
               WHERE i = ANY(CAST(? AS uuid[])))    AS disliked_ingredient_count,
             ratings.avg_rating
      FROM items
      LEFT JOIN (
        SELECT reviews.item_id, AVG(reviews.rating)::float8 AS avg_rating
        FROM reviews
        WHERE reviews.hidden_at IS NULL
        GROUP BY reviews.item_id
      ) ratings ON ratings.item_id = items.id
      WHERE items.restaurant_id = ?
        AND items.status = 'published'
    ) scored
  SQL

  # Returns { item_id => { score: Float,
  #                        matched_liked_tag_ids: [...],
  #                        matched_liked_ingredient_ids: [...] } }
  # for every published item at the restaurant. One query; the
  # matched arrays feed the "because you like…" line client-side.
  def self.scores_for(restaurant_id:, signals:)
    sql = ActiveRecord::Base.sanitize_sql_array([
      SCORES_SQL,
      WEIGHTS[:liked_tag], WEIGHTS[:liked_ingredient],
      WEIGHTS[:disliked_tag], WEIGHTS[:disliked_ingredient],
      WEIGHTS[:rating],
      pg_uuid_array(signals.liked_tag_ids),
      pg_uuid_array(signals.liked_ingredient_ids),
      pg_uuid_array(signals.disliked_tag_ids),
      pg_uuid_array(signals.disliked_ingredient_ids),
      restaurant_id
    ])

    ActiveRecord::Base.connection.select_all(sql).rows.to_h do |id, score, tags, ings|
      [id, {
        score:                        score.to_f,
        matched_liked_tag_ids:        parse_uuid_array(tags),
        matched_liked_ingredient_ids: parse_uuid_array(ings)
      }]
    end
  end

  # "{a,b}" — the PG array-literal string form CAST(? AS uuid[])
  # accepts. Inputs are validated UUIDs (Phase 8.1) and the whole
  # string goes through a sanitized placeholder regardless.
  def self.pg_uuid_array(ids)
    "{#{Array(ids).join(',')}}"
  end
  private_class_method :pg_uuid_array

  # select_all returns uuid[] as the wire string "{a,b}". UUIDs never
  # contain commas/braces, so a plain split is exact.
  def self.parse_uuid_array(value)
    return value if value.is_a?(Array)
    value.to_s.delete("{}").split(",").reject(&:empty?)
  end
  private_class_method :parse_uuid_array
end
