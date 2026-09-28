# frozen_string_literal: true

module Tools
  module Discovery
    class ListCities < Tools::Base
      audience :public

      tool_name "list_cities"
      title "List the cities we cover"
      description <<~TEXT
        Every city Biteworthy covers, with its slug and how many restaurants
        are published there. A city with zero published restaurants is real
        and open for new ones — `search_restaurants` cannot see it, so use
        this to find the `city_slug` that `create_restaurant` needs.

        If the user's city is not listed, say so plainly. Admins can add it
        with `create_city`; anyone else can ask an admin to.
      TEXT

      input_schema(properties: {})

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      running_description { "Looking up cities" }

      def self.perform(context:)
        counts = Restaurant.published.group(:city_id).count
        cities = City.order(:name).map do |city|
          city.summary.merge(published_restaurants: counts[city.id] || 0)
        end
        ok(cities: cities)
      end
    end
  end
end
