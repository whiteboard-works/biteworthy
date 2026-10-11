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

        A multi-location brand is one Restaurant row per physical spot. When
        the brand name would collide, include a neighborhood or street in
        `name` (e.g. "Caracas Grill — Riverton"). Same brand in different
        cities is expected — only `force` after the user confirms they are
        distinct spots.

        Website, phone, and hours can be set here so a community import does
        not need admin `edit_place`. Hours replace the whole week.

        A logo and a banner can be set here too: pass the ids of images the
        user uploaded through the app (`logo_attachment_id`,
        `banner_attachment_id`). Ask for them when importing a restaurant so
        the listing is as complete as possible; `set_restaurant_branding`
        adds or changes them later while the restaurant is still your draft.
      TEXT

      HOUR_ROW = {
        type: "object",
        properties: {
          day_of_week: { type: "integer", description: "0 = Sunday … 6 = Saturday.", minimum: 0, maximum: 6 },
          opens_at:    { type: "string", description: "24-hour HH:MM. Omit both times for a closed day." },
          closes_at:   { type: "string", description: "24-hour HH:MM." }
        },
        required: [ "day_of_week" ]
      }.freeze

      input_schema(
        properties: {
          name:        { type: "string", description: "The restaurant's name as it appears on the sign. Distinguish siblings with a neighborhood or street." },
          city_slug:   { type: "string", description: "City slug, e.g. 'durango'. From list_cities." },
          street:      { type: "string", description: "Street address, if known." },
          postal_code: { type: "string", description: "Postal code, if known." },
          website:     { type: "string", description: "The restaurant's own website URL, if known." },
          phone:       { type: "string", description: "Phone number, if known." },
          hours: {
            type: "array",
            description: "The FULL week of opening hours, if known. Replaces every existing row.",
            items: HOUR_ROW
          },
          logo_attachment_id: {
            type: "string",
            description: "Id of an uploaded image to use as the logo. You cannot invent these — " \
                         "if the user has not uploaded one, ask them to."
          },
          banner_attachment_id: {
            type: "string",
            description: "Id of an uploaded image to use as the banner (wide, about 8:3)."
          },
          force: {
            type: "boolean",
            description: "Skip the duplicate check. Only after the user has reviewed the candidates."
          }
        },
        required: %w[name city_slug]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      running_description { |args| args[:name].to_s.strip.present? ? "Adding #{args[:name].to_s.strip.truncate(30)}" : "Adding the restaurant" }

      def self.perform(context:, name:, city_slug:, street: nil, postal_code: nil,
                       website: nil, phone: nil, hours: nil, force: false,
                       logo_attachment_id: nil, banner_attachment_id: nil)
        user = context.user!
        logo   = logo_attachment_id.present? ? owned_upload!(logo_attachment_id, user) : nil
        banner = banner_attachment_id.present? ? owned_upload!(banner_attachment_id, user) : nil

        # One transaction around the create and the images: an upload that
        # turns out not to be an image (the scan door also accepts PDFs)
        # refuses the whole call instead of leaving a draft behind with no
        # images, which the retry would then trip over as a duplicate.
        result = Restaurant.transaction do
          created = ::Restaurants::Create.call(
            name: name, city_slug: city_slug, creator: user,
            street: street, postal_code: postal_code, force: force,
            website: website, phone: phone, hours: hours
          )
          if created.restaurant && (logo || banner)
            # The creator passes as the draft's creator; going through the
            # gate keeps Branding's rule the only one.
            ::Restaurants::Branding.authorize!(user, created.restaurant)
            ::Restaurants::Branding.apply!(created.restaurant, logo: logo, banner: banner)
          end
          created
        end

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
            status: restaurant.status, city: restaurant.city.slug,
            website: restaurant.website, phone: restaurant.phone,
            logo_url:   ::Restaurants::Branding.variant_url(restaurant.logo, :thumb, host: context.public_host),
            banner_url: ::Restaurants::Branding.variant_url(restaurant.banner, :card, host: context.public_host)
          },
          next_step: "Scan its menu with start_menu_scan to move it out of draft."
        )
      rescue Images::StripMetadata::Unprocessable => e
        raise Errors::InvalidArgument, "That upload cannot be used as a logo or banner: #{e.message}"
      rescue ::Restaurants::Branding::Forbidden => e
        raise Errors::Forbidden, e.message
      rescue ArgumentError => e
        raise Errors::InvalidArgument, e.message
      rescue ::Restaurants::Create::UnknownCity => e
        raise Errors::InvalidArgument, "#{e.message}. Check list_cities; an admin can add a missing city with create_city."
      end
    end
  end
end
