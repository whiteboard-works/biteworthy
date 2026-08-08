# frozen_string_literal: true

module Tools
  module Restaurants
    class CreateRestaurant < Tools::Base
      audience :user

      tool_name "create_restaurant"
      title "Add a restaurant we don't have yet"
      description <<~TEXT
        Create a restaurant so a menu can be scanned into it. Search first with
        `search_restaurants` — most "missing" restaurants are already here under
        a slightly different name.

        The new restaurant lands as a DRAFT: it is not in search results and
        not on the city page until enough of its menu is verified. Say that,
        so the user is not surprised when they cannot find it.

        If the name looks like one we already have in that city, this returns
        `possible_duplicates` and creates nothing. Show the user the candidates
        and let them choose. Only call again with `force: true` after they have
        said it is genuinely a different place.
      TEXT

      input_schema(
        properties: {
          name:        { type: "string", description: "The restaurant's name as it appears on the sign." },
          city_slug:   { type: "string", description: "City slug, e.g. 'durango'. From search_restaurants." },
          street:      { type: "string", description: "Street address, if known." },
          postal_code: { type: "string", description: "Postal code, if known." },
          force: {
            type: "boolean",
            description: "Skip the duplicate check. Only after the user has reviewed the candidates."
          }
        },
        required: %w[name city_slug]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      def self.perform(context:, name:, city_slug:, street: nil, postal_code: nil, force: false)
        user = context.user!
        result = ::Restaurants::Create.call(
          name: name, city_slug: city_slug, creator: user,
          street: street, postal_code: postal_code, force: force
        )

        if result.duplicate?
          return ok(
            created: false,
            reason: "possible_duplicate",
            possible_duplicates: result.candidates,
            next_step: "Ask the user whether one of these is the place. If none is, call again with force: true."
          )
        end

        restaurant = result.restaurant
        ok(
          created: true,
          restaurant: {
            id: restaurant.id, slug: restaurant.slug, name: restaurant.name,
            status: restaurant.status, city: restaurant.city.slug
          },
          next_step: "Scan its menu with start_menu_scan to move it out of draft."
        )
      rescue ArgumentError => e
        raise Errors::InvalidArgument, e.message
      rescue ::Restaurants::Create::UnknownCity => e
        raise Errors::InvalidArgument, "#{e.message}. Biteworthy only covers a few cities so far."
      end
    end
  end
end
