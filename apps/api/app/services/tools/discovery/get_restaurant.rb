# frozen_string_literal: true

module Tools
  module Discovery
    # One restaurant's header details. Deliberately does not include the
    # menu — menus are large and get_menu takes filtering arguments this
    # tool has no business guessing.
    class GetRestaurant < Tools::Base
      audience :public

      tool_name "get_restaurant"
      title "Get restaurant details"
      description <<~TEXT
        Fetch one published restaurant by id or slug: name, city, contact
        details, and whether an owner has claimed it. Use `get_menu` for the
        dishes.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: 'Restaurant UUID or slug, e.g. "ninis-taqueria".'
          }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, restaurant:)
        record = Restaurant.published.includes(:city, :addresses).find_by_id_or_slug!(restaurant)
        address = record.addresses.first

        ok(
          id:       record.id,
          slug:     record.slug,
          name:     record.name,
          about:    record.about,
          phone:    record.phone,
          website:  record.website,
          claimed:  !record.claimed_at.nil?,
          city:     { slug: record.city.slug, name: record.city.name, region: record.city.region },
          street:   address&.street,
          saved_by_caller: context.signed_in? &&
            FavoriteRestaurant.exists?(user_id: context.user.id, restaurant_id: record.id)
        )
      end
    end
  end
end
