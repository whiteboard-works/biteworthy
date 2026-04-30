# frozen_string_literal: true

# Phase 5.6 — rank a city's published restaurants by how many of
# their items pass a given dietary preset's filter.
#
# Returns a deterministic order — `(visible_count DESC, name ASC)` —
# so the same SEO page renders identically across requests / regions.
#
# One SQL query: filter logic mirrors `Items::FILTERED` in spirit but
# applies it at the count level so we don't N+1 (running the items
# endpoint 30 times during SSR would tank the page).
#
# The aggregate uses Postgres `FILTER (WHERE ...)` clauses against
# the `items.ingredient_ids uuid[]` + `items.tag_ids uuid[]` GIN
# arrays the schema is shaped around (see `docs/schema.md`).
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
      avoid_ingredient_ids = @profile.dietary_profile_ingredients.where(rule: "avoid").pluck(:ingredient_id)
      avoid_tag_ids        = @profile.dietary_profile_tags.where(rule: "avoid").pluck(:tag_id)

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
