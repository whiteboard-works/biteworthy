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
        A listing or a diet ranking with no `city_slug` uses the caller's home
        city when they have one and the credential can read their profile
        (`profile:read`; the first-party chat always can); a `query` by name
        is never limited to it. The result says which `city` was applied and
        why (`city_source`). Pass `anywhere: true` to list across every city.

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
            description: 'City to scope to, e.g. "durango". Omit to use the caller\'s home city when they have one and the credential can read their profile.'
          },
          diet: {
            type: "string",
            description: "Dietary preset slug to rank by. Needs a city: city_slug, or the caller's home city."
          },
          limit: {
            type: "integer",
            description: "Maximum results (1-25, default 10).",
            minimum: 1,
            maximum: 25
          },
          anywhere: {
            type: "boolean",
            description: "List across every city, ignoring the caller's home city. Cannot rank by diet."
          }
        },
        required: []
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { |args| args[:query].present? ? "Searching for #{args[:query]}" : "Looking for places to eat" }

      MAX_LIMIT     = 25
      DEFAULT_LIMIT = 10

      def self.perform(context:, query: nil, city_slug: nil, diet: nil, limit: nil, anywhere: false)
        capped = (limit || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
        # "What's nearby" with no city named means the one they live in. A
        # search by name does not: someone asking about a place they know
        # should find it wherever it is. Either way the result says which
        # city was applied, so an empty answer is never mistaken for
        # "nowhere" when it means "not here".
        if anywhere && city_slug.present?
          raise Errors::InvalidArgument, "Pass city_slug or anywhere: true, not both."
        end

        source = "argument" if city_slug.present?
        if city_slug.blank? && query.blank? && !anywhere && (home = home_city_slug(context))
          city_slug = home
          source    = "home_city"
        end
        applied = { city: city_slug.presence, city_source: source }.compact

        return ranked_by_diet(city_slug, diet, capped, applied) if diet.present?

        scope = Restaurant.published.includes(:city, :addresses)
        scope = scope.joins(:city).where(cities: { slug: city_slug }) if city_slug.present?
        if query.present?
          scope = scope.where("restaurants.name ILIKE ?", "%#{Restaurant.sanitize_sql_like(query)}%")
        end

        ok(applied.merge(restaurants: scope.order(:name).limit(capped).map { |r| summary(r) }))
      end

      def self.ranked_by_diet(city_slug, diet, limit, applied = {})
        raise Errors::InvalidArgument, "city_slug is required when ranking by diet." if city_slug.blank?

        city = City.find_by(slug: city_slug)
        raise Errors::NotFound, "No city with slug #{city_slug.inspect}." if city.nil?

        preset = DietaryProfile.find_by(slug: diet)
        raise Errors::NotFound, "No dietary preset with slug #{diet.inspect}. Try search_taxonomy." if preset.nil?

        # Ranking is a single grouped query over the whole city; slicing
        # in Ruby keeps the `visible_count DESC, name ASC` order intact.
        ranked = Cities::RestaurantRanking.new(city: city, dietary_profile: preset).call.first(limit)

        ok(
          **applied,
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

      # Profile data, so it stays behind the profile scope: a credential
      # granted only discovery must not learn where its owner lives from
      # a listing that quietly defaulted to it.
      def self.home_city_slug(context)
        return nil unless Tools::Scopes.satisfied?(context.scopes, "profile:read")

        context.user&.profile&.home_city&.slug
      end
      private_class_method :home_city_slug

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
