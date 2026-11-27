# frozen_string_literal: true

module Tools
  module Admin
    # Edit restaurant details: name, about, website, phone, city, address.
    # Reuses the REST admin update (immutable slug, ReassignCity) and
    # Places::Writer for wholesale address replacement.
    class UpdateRestaurant < Tools::AdminBase
      tool_name "update_restaurant"
      title "Edit restaurant details"
      description <<~TEXT
        Update a restaurant's name, about text, website, phone, city, or address.

        `city` is a city slug or UUID — it moves the restaurant to that city.
        The city must already exist in the same state and country. The
        restaurant slug does not change, so the old city URL redirects.

        Address is REPLACED wholesale when you provide address fields — a
        partial update leaves the unmentioned fields alone, but providing any
        address field is a signal to overwrite that whole facet.

        Slug is immutable. Status changes go through set_restaurant_status.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          name: { type: "string" },
          about: { type: "string" },
          website: { type: "string" },
          phone: { type: "string" },
          street: { type: "string" },
          city: {
            type: "string",
            description: "City slug or UUID. Moves the restaurant to that city " \
                         "(must exist, same state/country). Restaurant slug unchanged."
          },
          region: { type: "string" },
          postal_code: { type: "string" },
          country: { type: "string" },
          latitude: { anyOf: [ { type: "number" }, { type: "string" } ] },
          longitude: { anyOf: [ { type: "number" }, { type: "string" } ] },
          map_provider_place_id: { type: "string" }
        },
        required: [ "restaurant" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { |args| "Updating #{args[:restaurant]}" }

      def self.perform(context:, restaurant:, **attrs)
        context.admin!
        record = find_restaurant!(restaurant)

        record = Restaurant.transaction do
          base_attrs = {}
          %i[name about website phone].each do |field|
            base_attrs[field] = attrs[field] if attrs.key?(field)
          end
          record.update!(base_attrs) if base_attrs.any?

          record = reassign_city!(record, attrs[:city]) if attrs.key?(:city)

          # `city` is the City row, not address.city text. Other address
          # fields still go through Places::Writer; when a city move was
          # requested, stamp the city's name onto the address so the
          # street line cannot stay on Ogden after the URL says Draper.
          address_keys = %i[street region postal_code country latitude longitude map_provider_place_id]
          writer_attrs = attrs.slice(*address_keys)
          writer_attrs[:city] = record.city.name if attrs.key?(:city)
          if writer_attrs.any?
            record = Places::Writer.replace_address!(record, writer_attrs)
          end
          record
        end

        ok(serialize_restaurant(record))
      rescue Places::Writer::InvalidInput => e
        raise Errors::InvalidArgument, "#{e.error}: #{e.values.join(', ')}"
      end

      def self.serialize_restaurant(restaurant)
        Places::Writer.serialize(restaurant).merge(
          slug:   restaurant.slug,
          name:   restaurant.name,
          about:  restaurant.about,
          website: restaurant.website,
          phone:  restaurant.phone,
          status: restaurant.status,
          city:   restaurant.city.summary,
          web_path: restaurant.web_path
        )
      end
      private_class_method :serialize_restaurant
    end
  end
end
