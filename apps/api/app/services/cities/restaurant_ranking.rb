# frozen_string_literal: true

# Phase 5.6 — rank a city's published restaurants by how many of
# their items pass a given dietary preset's filter.
#
# Returns a deterministic order — `(visible_count DESC, name ASC)` —
# so the same SEO page renders identically across requests / regions.
#
# One SQL query, because the alternative is running the menu query
# thirty times during SSR. The aggregate uses Postgres
# `FILTER (WHERE ...)` clauses against the `items.ingredient_ids uuid[]`
# + `items.tag_ids uuid[]` GIN arrays the schema is shaped around (see
# `docs/schema.md`).
#
# **`visible_count` must mean the same thing here as on the restaurant
# page**, or a /durango/vegan card promises more dishes than the menu
# behind it delivers. Two halves to that:
#
#   * **Subtree expansion applies.** The avoid lists go through
#     `Menus::Filter.resolve_subtrees` — the same entry point
#     `Menus::Filter.build` uses — so avoiding `dairy` counts a dish
#     tagged `dairy.cheddar` as hidden. This used to read the profile's
#     raw ids, which happened to work only because presets are stored
#     pre-expanded (`Menus::Subtree`'s note); any non-preset avoid set
#     reaching here would have over-counted.
#   * **The confidence rule intentionally does not.** It only fires
#     under `strictness: "strict"`, and strictness is a property of a
#     *person* — a `DietaryProfile` preset has no such column, and both
#     callers (the anonymous SEO endpoint and the `search_restaurants`
#     tool) pass a preset. The filter this ranking counts is therefore
#     `balanced` by construction, exactly like
#     `Menus::Filter.from_preset`, where the confidence clause is a
#     no-op. Nothing to skip, so nothing is skipped. If a signed-in
#     user's own profile is ever ranked here, that stops being true and
#     the count needs an `items.confidence = 'confirmed'` clause.
module Cities
  class RestaurantRanking
    Ranked = Struct.new(:restaurant, :visible_count, :total_count, keyword_init: true) do
      def hidden_count
        total_count - visible_count
      end
    end

    def initialize(city:, dietary_profile:)
      @city    = city
      @profile = dietary_profile
    end

    # Returns an Array<Ranked>. Empty when the city has no published
    # restaurants.
    def call
      avoid_ingredient_ids = filter.avoid_ingredient_ids
      avoid_tag_ids        = filter.avoid_tag_ids

      rows = Restaurant
        .published
        .where(city_id: @city.id)
        .left_outer_joins(:items)
        .merge(published_items_or_null)
        .group("restaurants.id")
        .select(
          "restaurants.id",
          visible_count_sql(avoid_ingredient_ids, avoid_tag_ids),
          total_count_sql
        )
        .order("visible_count DESC, restaurants.name ASC")

      restaurants_by_id = Restaurant.includes(:city).where(id: rows.map(&:id)).index_by(&:id)
      rows.map do |row|
        Ranked.new(
          restaurant:    restaurants_by_id[row.id],
          visible_count: row.visible_count.to_i,
          total_count:   row.total_count.to_i
        )
      end
    end

    private

    # The same Filter the menu endpoint would build for this preset, so
    # the counts here and the item list there answer to one definition.
    #
    # Memoized because `resolve_subtrees` costs two queries per taxonomy,
    # and for every preset shipping today the expansion is a no-op — the
    # seeds store them pre-expanded, so `path <@ ANY(...)` re-derives the
    # ids it was handed. Four queries per page for a guarantee rather than
    # a coincidence is the right trade; four per row would not be. If the
    # SEO pages ever become latency-sensitive, cache the expanded set per
    # preset rather than dropping the call.
    def filter
      @filter ||= Menus::Filter.resolve_subtrees(
        Menus::Filter.new(
          avoid_ingredient_ids: @profile.avoid_ingredient_ids,
          avoid_tag_ids:        @profile.avoid_tag_ids,
          strictness:           Menus::Filter::DEFAULT_STRICTNESS,
          source:               "preset",
          preset_slug:          @profile.slug
        )
      )
    end

    # `LEFT OUTER JOIN items` so restaurants with zero published items
    # still show up. Filter the joined items down to published-only
    # via WHERE on the items half of the join — a NULLs-permissive
    # condition (the OR i.id IS NULL preserves no-items restaurants).
    def published_items_or_null
      Restaurant.where("items.status = 'published' OR items.id IS NULL")
    end

    def visible_count_sql(avoid_ingredient_ids, avoid_tag_ids)
      avoid_ing_array = sanitize_uuid_array(avoid_ingredient_ids)
      avoid_tag_array = sanitize_uuid_array(avoid_tag_ids)

      <<~SQL.squish + " AS visible_count"
        COUNT(items.id) FILTER (
          WHERE items.id IS NOT NULL
            AND items.status = 'published'
            AND NOT (items.ingredient_ids && ARRAY[#{avoid_ing_array}]::uuid[])
            AND NOT (items.tag_ids        && ARRAY[#{avoid_tag_array}]::uuid[])
        )
      SQL
    end

    def total_count_sql
      "COUNT(items.id) FILTER (WHERE items.id IS NOT NULL AND items.status = 'published') AS total_count"
    end

    # ARRAY[]::uuid[] doesn't accept an empty list inline — emit a
    # safe placeholder UUID that no real row will match. Otherwise
    # quote each id so it interpolates safely.
    def sanitize_uuid_array(ids)
      return "'00000000-0000-0000-0000-000000000000'" if ids.blank?
      ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(",")
    end
  end
end
