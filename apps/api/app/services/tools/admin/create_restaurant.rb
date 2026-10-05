# frozen_string_literal: true

module Tools
  module Admin
    # Create a restaurant (admin version). Reuses the same duplicate detection
    # and force override as the user tool, but accessible in the admin domain.
    class CreateRestaurant < Tools::AdminBase
      tool_name "create_restaurant"
      title "Create a restaurant (admin)"
      description <<~TEXT
        Create a restaurant so a menu can be scanned into it. Search first with
        find_restaurants to avoid duplicates.

        The new restaurant lands as DRAFT: not in search results, not on the
        city page, until enough of its menu is verified.

        If the name looks like one already in that city, this returns
        possible_duplicates with candidate matches and creates nothing. Review
        the candidates and call again with force: true only if it is genuinely
        a different place.
      TEXT

      input_schema(
        properties: {
          name: {
            type: "string",
            description: "Restaurant name as it appears on the sign."
          },
          city_slug: {
            type: "string",
            description: "City slug, e.g. 'durango'. From list_cities."
          },
          street: {
            type: "string",
            description: "Street address, if known."
          },
          postal_code: {
            type: "string",
            description: "Postal code, if known."
          },
          force: {
            type: "boolean",
            description: "Skip duplicate check. Only after reviewing candidates."
          }
        },
        required: %w[name city_slug]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      running_description { |args| args[:name].to_s.strip.present? ? "Creating #{args[:name].to_s.strip.truncate(30)}" : "Creating restaurant" }

      def self.perform(context:, name:, city_slug:, street: nil, postal_code: nil, force: false)
        user = context.user!
        result = ::Restaurants::Create.call(
          name: name,
          city_slug: city_slug,
          creator: user,
          street: street,
          postal_code: postal_code,
          force: force
        )

        if result.duplicate?
          return ok(
            created: false,
            reason: "possible_duplicate",
            possible_duplicates: result.candidates.map do |candidate|
              {
                id: candidate[:id],
                slug: candidate[:slug],
                name: candidate[:name],
                street: candidate[:street],
                status: candidate[:status]
              }
            end,
            next_step: "Review candidates. If none match, call again with force: true."
          )
        end

        restaurant = result.restaurant
        ok(
          created: true,
          restaurant: {
            id: restaurant.id,
            slug: restaurant.slug,
            name: restaurant.name,
            status: restaurant.status,
            city: restaurant.city.slug
          },
          next_step: "Scan its menu with start_scan to move it out of draft."
        )
      rescue ArgumentError => e
        raise Errors::InvalidArgument, e.message
      rescue ::Restaurants::Create::UnknownCity => e
        raise Errors::InvalidArgument, "#{e.message}. Check list_cities; an admin can add a missing city with create_city."
      end
    end
  end
end
