# frozen_string_literal: true

# Creating a restaurant from the community "scan a new place" path.
#
# Extracted from RestaurantsController#create when the MCP tool layer
# needed the same behaviour: the duplicate guard, the slug generator, and
# the draft status are policy, and a second copy of them would drift.
# Both the REST endpoint and `create_restaurant` call this.
module Restaurants
  class Create
    class UnknownCity < StandardError; end

    # Calibrated against pg_trgm similarity() on realistic pairs:
    # true duplicates ("Maria's Tacos"/"Marias Taco" 0.53,
    # "Home Slice Pizza"/"Home Slice" 0.65, "Oscar's Cafe"/"Oscars Café"
    # 0.50) sit above 0.45; genuinely different restaurants ("Durango
    # Diner"/"Durango Bagel" 0.42, "Thai Kitchen"/"Himalayan Kitchen"
    # 0.35) sit below. This is a "did you mean?" prompt with a force
    # override, not a hard block, so a borderline match costs one extra tap.
    DUPLICATE_SIMILARITY_THRESHOLD = 0.45
    MAX_DUPLICATE_CANDIDATES       = 5

    Result = Struct.new(:restaurant, :candidates, keyword_init: true) do
      def duplicate? = restaurant.nil?
    end

    class << self
      def call(name:, city_slug:, creator:, street: nil, postal_code: nil, force: false)
        clean = name.to_s.strip
        raise ArgumentError, "name required" if clean.blank?

        city = City.find_by(slug: city_slug.to_s)
        raise UnknownCity, "no city with slug '#{city_slug}'" if city.nil?

        unless force
          candidates = duplicate_candidates(clean, city)
          return Result.new(candidates: candidates) if candidates.any?
        end

        restaurant = Restaurant.create!(
          name: clean, slug: unique_slug_for(clean, city), city: city,
          status: "draft", created_by_user_id: creator.id
        )
        attach_address!(restaurant, city, street, postal_code)
        Result.new(restaurant: restaurant, candidates: [])
      end

      def duplicate_candidates(name, city)
        Restaurant
          .where(city: city)
          .where("similarity(restaurants.name, ?) > ?", name, DUPLICATE_SIMILARITY_THRESHOLD)
          .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array(
                            ["similarity(restaurants.name, ?) DESC", name]
                          )))
          .limit(MAX_DUPLICATE_CANDIDATES)
          .includes(:addresses)
          .map do |r|
            { id: r.id, slug: r.slug, name: r.name, status: r.status, street: r.addresses.first&.street }
          end
      end

      private

      # `parameterize`, then the city on collision, then a number:
      # "ninis", "taco-bell-durango", "taco-bell-durango-2".
      #
      # The collision that matters is a chain, not a name: every city has
      # a Taco Bell, so the second one used to become `taco-bell-2` — a
      # slug that says nothing about which one it is, in a URL people see
      # and share. Reaching for the city first makes the disambiguator
      # mean something, and it is the disambiguator a person would have
      # picked.
      #
      # **`restaurants.slug` stays globally unique, deliberately.** The
      # obvious reading of "city-scope the slug" is a `[city_id, slug]`
      # index, and that breaks lookup: `find_by_id_or_slug!` and the web
      # route `/restaurants/[slug]` carry no city, so a per-city-unique
      # slug makes `find_by!(slug:)` ambiguous — it would return whichever
      # row Postgres reached first, silently, which for a filtered menu is
      # the wrong restaurant's dietary data. Making generation
      # city-aware solves the collision the roadmap actually named
      # (city #2 is blocked) without moving the uniqueness the routes
      # depend on, and every URL already issued keeps working.
      #
      # The numeric tail survives for the case the city cannot settle:
      # two Taco Bells in one city. The city is only reached for when the
      # collision is genuinely across cities — appending "durango" to tell
      # two Durango restaurants apart names the thing they have in common,
      # which is a worse label than a number and a misleading one besides.
      def unique_slug_for(name, city)
        base = name.parameterize
        base = "restaurant" if base.blank?
        return base unless Restaurant.exists?(slug: base)

        unless Restaurant.exists?(slug: base, city_id: city.id)
          with_city = [ base, city.slug.parameterize ].join("-")
          return with_city unless Restaurant.exists?(slug: with_city)
        end

        numbered(with_city || base)
      end

      def numbered(base)
        n = 2
        n += 1 while Restaurant.exists?(slug: "#{base}-#{n}")
        "#{base}-#{n}"
      end

      def attach_address!(restaurant, city, street, postal_code)
        street = street.to_s.strip.presence
        postal = postal_code.to_s.strip.presence
        return if street.nil? && postal.nil?

        restaurant.addresses.create!(
          street: street, postal_code: postal, city: city.name, region: city.region
        )
      end
    end
  end
end
