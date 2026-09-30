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

        Pass `near_me: true` when the caller has shared their device location
        (the prompt says so) and asks for somewhere close. Results are then
        nearest first with `distance_km`, limited to `radius_km` (default 40)
        unless a `city_slug` is named; the caller's home city is not applied.
        `distance_km: null` means we have no coordinates for that restaurant:
        its city is within range, but the restaurant itself may not be. A diet
        ranking with `near_me` ranks within the nearest city and adds
        `distance_km`. Without a shared location `near_me` is refused; ask the
        caller to tap "Use my location", or to name a city.

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
          },
          near_me: {
            type: "boolean",
            description: "Sort nearest first from the caller's shared device location. Refused when none was shared."
          },
          radius_km: {
            type: "number",
            description: "With near_me and no city_slug: how far to look (1-200 km, default 40).",
            minimum: 1,
            maximum: 200
          }
        },
        required: []
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { |args| args[:query].present? ? "Searching for #{args[:query]}" : "Looking for places to eat" }

      MAX_LIMIT     = 25
      DEFAULT_LIMIT = 10
      DEFAULT_RADIUS_KM = 40
      MAX_RADIUS_KM     = 200
      KM_PER_DEGREE     = 111.0

      NO_LOCATION = "The caller has not shared their location with this message. Ask them to tap " \
                    "\"Use my location\" next to the message box, or to name a city."

      def self.perform(context:, query: nil, city_slug: nil, diet: nil, limit: nil, anywhere: false,
                       near_me: false, radius_km: nil)
        capped = (limit || DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
        if near_me
          raise Errors::InvalidArgument, "Pass near_me or anywhere: true, not both." if anywhere
          here = context.device_location
          raise Errors::InvalidArgument, NO_LOCATION if here.blank?

          radius = (radius_km || DEFAULT_RADIUS_KM).to_f.clamp(1, MAX_RADIUS_KM)
          return near(here, radius, query: query, city_slug: city_slug, diet: diet, limit: capped)
        end

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

      # Distance only where the restaurant has coordinates. A restaurant
      # without them is still listed when its city is in range, after
      # every one that has them, so a thin coordinate backfill shows up as
      # "distance unknown" rather than as an empty answer.
      def self.near(here, radius, query:, city_slug:, diet:, limit:)
        if diet.present?
          source = "argument" if city_slug.present?
          if city_slug.blank?
            city_slug = nearest_city_slug(here, radius)
            raise Errors::NotFound, "No city within #{radius.round} km of the caller. Try list_cities." if city_slug.nil?
            source = "device_location"
          end
          applied = { city: city_slug, city_source: source, sorted_by: "passing_item_count" }
          return ranked_by_diet(city_slug, diet, limit, applied, here: here)
        end

        scope = Restaurant.published.includes(:city, :addresses)
        scope = scope.joins(:city).where(cities: { slug: city_slug }) if city_slug.present?
        if query.present?
          scope = scope.where("restaurants.name ILIKE ?", "%#{Restaurant.sanitize_sql_like(query)}%")
        end
        scope = within_box(scope, here, radius) if city_slug.blank?

        rows = scope.to_a.filter_map do |restaurant|
          distance = distance_km(restaurant, here)
          if city_slug.blank?
            next if distance && distance > radius
            next if distance.nil? && !city_within?(restaurant.city, here, radius)
          end
          [ restaurant, distance ]
        end
        rows.sort_by! { |restaurant, distance| [ distance.nil? ? 1 : 0, distance || 0, restaurant.name ] }

        applied = { sorted_by: "distance" }
        applied[:radius_km] = radius if city_slug.blank?
        applied.merge!(city: city_slug, city_source: "argument") if city_slug.present?
        ok(**applied, restaurants: rows.first(limit).map { |restaurant, distance| summary(restaurant).merge(distance_km: distance&.round(1)) })
      end
      private_class_method :near

      # A cheap SQL cut before the exact distance in Ruby. Either the
      # restaurant has an address in the box, or it has none with
      # coordinates and its city is in the box.
      def self.within_box(scope, here, radius)
        dlat = radius / KM_PER_DEGREE
        dlng = radius / (KM_PER_DEGREE * [ Math.cos(here["lat"] * Math::PI / 180).abs, 0.01 ].max)
        box  = [ here["lat"] - dlat, here["lat"] + dlat, here["lng"] - dlng, here["lng"] + dlng ]
        in_box = "latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?"

        by_address = Address.where(in_box, *box).select(:restaurant_id)
        by_city    = City.where(in_box, *box).select(:id)
        scope.where(id: by_address).or(scope.where(city_id: by_city))
      end
      private_class_method :within_box

      def self.nearest_city_slug(here, radius)
        City.where.not(latitude: nil).where.not(longitude: nil)
            .map { |city| [ city, Geo.distance_km(here["lat"], here["lng"], city.latitude, city.longitude) ] }
            .select { |_, distance| distance <= radius }
            .min_by { |_, distance| distance }
            &.first&.slug
      end
      private_class_method :nearest_city_slug

      def self.city_within?(city, here, radius)
        return false if city.latitude.nil? || city.longitude.nil?

        Geo.distance_km(here["lat"], here["lng"], city.latitude, city.longitude) <= radius
      end
      private_class_method :city_within?

      def self.distance_km(restaurant, here)
        address = restaurant.addresses.find { |a| a.latitude && a.longitude }
        return nil if address.nil?

        Geo.distance_km(here["lat"], here["lng"], address.latitude, address.longitude)
      end
      private_class_method :distance_km

      def self.ranked_by_diet(city_slug, diet, limit, applied = {}, here: nil)
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
            row_summary = summary(row.restaurant).merge(
              passing_item_count: row.visible_count,
              total_item_count:   row.total_count
            )
            here ? row_summary.merge(distance_km: distance_km(row.restaurant, here)&.round(1)) : row_summary
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
