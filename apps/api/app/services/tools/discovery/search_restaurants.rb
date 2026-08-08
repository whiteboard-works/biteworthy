# frozen_string_literal: true

module Tools
  module Discovery
    # Find a restaurant by name, or list what's published in a city.
    #
    # When `diet` names a preset, results are ranked by how many dishes
    # survive that preset's avoid lists — Cities::RestaurantRanking answers
    # that in one SQL pass instead of a get_menu call per restaurant, which
    # is the difference between one query and thirty.
    class SearchRestaurants < Tools::Base
      audience :public

      tool_name "search_restaurants"
      title "Search restaurants"
      description <<~TEXT
        Find published restaurants by name and/or city. Call this first when
        the user names a place, asks what's nearby, or asks where they can eat
        something — you need a restaurant id or slug before you can read a menu.

        Pass `diet` (a dietary preset slug such as "vegan" or "gluten-free") to
        rank results by how many dishes pass that preset rather than by name;
        each result then carries `passing_item_count` out of `total_item_count`.
        Use `search_taxonomy` if you need to discover which preset slugs exist.
      TEXT

      input_schema(
        properties: {
          query: {
            type: "string",
            description: "Case-insensitive substring match on the restaurant name. Omit to list everything in the city."
          },
          city_slug: {
            type: "string",
            description: 'City to scope to, e.g. "durango". Required when ranking by diet.'
          },
          diet: {
            type: "string",
            description: "Dietary preset slug to rank by. Requires city_slug."
          },
          limit: {
            type: "integer",
            description: "Maximum results (1-25, default 10).",
            minimum: 1,
            maximum: 25
          }
        },
        required: []
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      MAX_LIMIT     = 25
      DEFAULT_LIMIT = 10

      def self.perform(context:, query: nil, city_slug: nil, diet: nil, limit: nil)
        capped = (limit || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)

        return ranked_by_diet(city_slug, diet, capped) if diet.present?

        scope = Restaurant.published.includes(:city, :addresses)
        scope = scope.joins(:city).where(cities: { slug: city_slug }) if city_slug.present?
        if query.present?
          scope = scope.where("restaurants.name ILIKE ?", "%#{Restaurant.sanitize_sql_like(query)}%")
        end

        ok(restaurants: scope.order(:name).limit(capped).map { |r| summary(r) })
      end

      def self.ranked_by_diet(city_slug, diet, limit)
        raise Errors::InvalidArgument, "city_slug is required when ranking by diet." if city_slug.blank?

        city = City.find_by(slug: city_slug)
        raise Errors::NotFound, "No city with slug #{city_slug.inspect}." if city.nil?

        preset = DietaryProfile.find_by(slug: diet)
        raise Errors::NotFound, "No dietary preset with slug #{diet.inspect}. Try search_taxonomy." if preset.nil?

        # Ranking is a single grouped query over the whole city; slicing
        # in Ruby keeps the `visible_count DESC, name ASC` order intact.
        ranked = Cities::RestaurantRanking.new(city: city, dietary_profile: preset).call.first(limit)

        ok(
          diet: preset.slug,
          restaurants: ranked.map do |row|
            summary(row.restaurant).merge(
              passing_item_count: row.visible_count,
              total_item_count:   row.total_count
            )
          end
        )
      end
      private_class_method :ranked_by_diet

      def self.summary(restaurant)
        address = restaurant.addresses.first
        {
          id:     restaurant.id,
          slug:   restaurant.slug,
          name:   restaurant.name,
          city:   restaurant.city.name,
          region: restaurant.city.region,
          street: address&.street
        }
      end
      private_class_method :summary
    end
  end
end
