# frozen_string_literal: true

module Tools
  module Restaurants
    class EditRestaurant < Tools::AdminBase
      tool_name "edit_restaurant"
      title "Edit a restaurant"
      description <<~TEXT
        Change a restaurant's name, description, contact details, city, or
        status. Omitted fields are left alone.

        `status` is the publish switch. "draft" hides it from search and city
        pages; "published" makes it public; "closed" marks a place that shut
        down. Publishing a restaurant whose menu is mostly unverified puts
        unchecked ingredient data in front of people who filter on it — check
        with `get_menu_structure` first.

        `city` is a city slug or UUID. The city must already exist in the same
        state and country; the restaurant slug does not change, so old city
        URLs redirect to the new `web_path`.

        The slug is permanent. It is the public URL and the lookup key, and
        renaming it breaks every link anyone saved.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant slug or UUID." },
          name:       { type: "string", description: "Display name." },
          about:      { type: "string", description: "Short description." },
          website:    { type: "string", description: "Website URL." },
          phone:      { type: "string", description: "Phone number." },
          status:     { type: "string", description: "Publish state.", enum: Restaurant::STATUSES },
          city:       { type: "string",
                        description: "City slug or UUID. Must exist in the same state and country. " \
                                     "The restaurant slug is unchanged." }
        },
        required: ["restaurant"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      running_description { "Updating the restaurant" }

      EDITABLE = %i[name about website phone status].freeze

      def self.perform(context:, restaurant:, **fields)
        context.admin!
        record = find_restaurant!(restaurant)

        attrs = fields.slice(*EDITABLE)
        if attrs.empty? && !fields.key?(:city)
          raise Errors::InvalidArgument, "Pass at least one field to change."
        end
        if attrs[:status] && Restaurant::STATUSES.exclude?(attrs[:status])
          raise Errors::InvalidArgument, "status must be one of: #{Restaurant::STATUSES.join(', ')}."
        end

        record = Restaurant.transaction do
          record.update!(attrs) if attrs.any?
          record = reassign_city!(record, fields[:city]) if fields.key?(:city)
          record
        end
        changed = attrs.keys
        changed = changed + [ :city ] if fields.key?(:city)
        ok(restaurant_row(record.reload).merge(
             changed: changed,
             city: record.city.summary,
             web_path: record.web_path
           ))
      end
    end
  end
end
