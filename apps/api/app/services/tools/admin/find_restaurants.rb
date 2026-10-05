# frozen_string_literal: true

module Tools
  module Admin
    # Search restaurants for admin work — includes drafts, archived, and
    # all statuses that public search filters out.
    class FindRestaurants < Tools::AdminBase
      tool_name "find_restaurants"
      title "Find restaurants (admin)"
      description <<~TEXT
        Search for restaurants by name or city for admin work. Unlike the
        public search, this includes drafts, archived, and closed restaurants
        so you can find and work on anything.

        Results include status (draft/published/closed) and whether a
        restaurant is archived.
      TEXT

      input_schema(
        properties: {
          q: {
            type: "string",
            description: "Name to search for, partial match is fine."
          },
          city_slug: {
            type: "string",
            description: "City slug to filter to, e.g. 'durango'. Omit to search all cities."
          },
          status: {
            type: "string",
            enum: Restaurant::STATUSES,
            description: "Filter by status: #{Restaurant::STATUSES.join(', ')}. Omit for all."
          },
          archived: {
            type: "boolean",
            description: "true = archived only, false or omit = kept only (default)."
          }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Searching restaurants" }

      def self.perform(context:, q: nil, city_slug: nil, status: nil, archived: nil)
        context.admin!
        scope = Restaurant.includes(:city).order(created_at: :desc)

        # Archived filter: three states: archived-only, kept-only (default), or both.
        # Default to kept-only when not specified.
        case archived
        when true  then scope = scope.archived
        when nil   then scope = scope.kept
        when false then scope = scope.kept
        end

        scope = scope.where(status: status) if Restaurant::STATUSES.include?(status.to_s)

        if city_slug.present?
          city = City.find_by!(slug: city_slug)
          scope = scope.where(city_id: city.id)
        end

        if q.present?
          query = "%#{ActiveRecord::Base.sanitize_sql_like(q.to_s.strip)}%"
          scope = scope.where("restaurants.name ILIKE :q", q: query)
        end

        restaurants = scope.limit(50).to_a
        ok(
          count: restaurants.size,
          restaurants: restaurants.map { |r| restaurant_row(r).merge(city: r.city&.slug) }
        )
      end
    end
  end
end
