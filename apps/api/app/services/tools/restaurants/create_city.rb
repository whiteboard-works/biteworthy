# frozen_string_literal: true

module Tools
  module Restaurants
    class CreateCity < Tools::AdminBase
      tool_name "create_city"
      title "Add a city we cover"
      description <<~TEXT
        Add a city so restaurants can be created in it. Call `list_cities`
        first — a second spelling of a city we already have ("SLC" next to
        "Salt Lake City") splits its restaurants across two pages.

        Use the city's full name as people write it ("Salt Lake City", not
        "SLC") and its US state as `region` ("Utah" or "UT"; stored as the
        full name). The slug is derived from the name and is permanent: it
        is part of every restaurant URL in the city.

        Adding a city publishes nothing on its own. Follow up with
        `create_restaurant` and a menu scan.
      TEXT

      input_schema(
        properties: {
          name:   { type: "string", description: "City name, e.g. 'Salt Lake City'." },
          region: { type: "string", description: "US state, e.g. 'Utah' or 'UT'." }
        },
        required: %w[name region],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      def self.perform(context:, name:, region:)
        context.admin!
        city = ::Cities::Create.call(name: name, region: region)
        ok(
          created: true,
          city: city.summary,
          next_step: "Add restaurants with create_restaurant using city_slug '#{city.slug}'."
        )
      rescue ::Cities::Create::Duplicate => e
        ok(created: false, reason: "already_exists", city: e.city.summary)
      rescue ArgumentError => e
        raise Errors::InvalidArgument, e.message
      end
    end
  end
end
