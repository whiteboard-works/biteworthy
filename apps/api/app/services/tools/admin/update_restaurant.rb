# frozen_string_literal: true

module Tools
  module Admin
    # Edit restaurant details: name, about, website, phone, address. Reuses
    # the same validation logic as the REST endpoint, including the immutable
    # slug and the wholesale address replacement.
    class UpdateRestaurant < Tools::AdminBase
      tool_name "update_restaurant"
      title "Edit restaurant details"
      description <<~TEXT
        Update a restaurant's name, about text, website, phone, or address.

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
          city: { type: "string" },
          region: { type: "string" },
          postal_code: { type: "string" },
          country: { type: "string" },
          latitude: { anyOf: [{ type: "number" }, { type: "string" }] },
          longitude: { anyOf: [{ type: "number" }, { type: "string" }] },
          map_provider_place_id: { type: "string" }
        },
        required: ["restaurant"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { |args| "Updating #{args[:restaurant]}" }

      def self.perform(context:, restaurant:, **attrs)
        record = find_restaurant!(restaurant)

        # Basic fields
        base_attrs = {}
        %i[name about website phone].each do |field|
          base_attrs[field] = attrs[field] if attrs.key?(field)
        end
        record.update!(base_attrs) if base_attrs.any?

        # Address replacement if any address field was sent
        address_keys = %i[street city region postal_code country latitude longitude map_provider_place_id]
        if (attrs.keys & address_keys).any?
          Places::Writer.replace_address!(record, attrs.slice(*address_keys))
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
          status: restaurant.status
        )
      end
      private_class_method :serialize_restaurant
    end
  end
end
