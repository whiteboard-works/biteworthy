# frozen_string_literal: true

module Tools
  module Structure
    class EditPlace < Tools::AdminBase
      tool_name "edit_place"
      title "Set a restaurant's address and opening hours"
      description <<~TEXT
        Update where a restaurant is, when it is open, or both. Read the
        current values back first — BOTH writes REPLACE what is there.

        Sending `hours` replaces the entire week. A day you leave out becomes
        "we have no hours for that day", not "unchanged". Send the whole week
        every time, including days that did not change.

        A day may carry several ranges — lunch 11:00–14:00 and dinner
        17:00–21:00 is an ordinary restaurant week. A day that is closed is
        one row with both times omitted. A day may not have both.

        Times are 24-hour "HH:MM". `day_of_week` is 0 for Sunday through 6 for
        Saturday. Bad input is rejected rather than coerced: "25:99" would
        otherwise silently become "closed", and a non-numeric latitude would
        put the restaurant in the Atlantic.
      TEXT

      HOUR_ROW = {
        type: "object",
        properties: {
          day_of_week: { type: "integer", description: "0 = Sunday … 6 = Saturday.", minimum: 0, maximum: 6 },
          opens_at:    { type: "string", description: "24-hour HH:MM. Omit both times for a closed day." },
          closes_at:   { type: "string", description: "24-hour HH:MM." }
        },
        required: ["day_of_week"]
      }.freeze

      input_schema(
        properties: {
          restaurant:  { type: "string", description: "Restaurant slug or UUID." },
          street:      { type: "string" },
          city:        { type: "string" },
          region:      { type: "string", description: "State or province." },
          postal_code: { type: "string" },
          country:     { type: "string" },
          latitude:    { type: "number" },
          longitude:   { type: "number" },
          hours: {
            type: "array",
            description: "The FULL week. Replaces every existing row.",
            items: HOUR_ROW
          }
        },
        required: ["restaurant"],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # Replaces the address and the week wholesale, which is destructive in
      # the annotation's sense — but re-sending them is the way back.
      unrecoverable_when { false }

      ADDRESS_KEYS = %i[street city region postal_code country latitude longitude].freeze

      def self.perform(context:, restaurant:, hours: nil, **address)
        context.admin!
        record = find_restaurant!(restaurant)

        attrs = address.slice(*ADDRESS_KEYS)
        if attrs.empty? && hours.nil?
          raise Errors::InvalidArgument, "Pass address fields, hours, or both."
        end

        record = ::Places::Writer.replace_address!(record, attrs) if attrs.any?
        record = ::Places::Writer.replace_hours!(record, hours)   unless hours.nil?

        ok(restaurant: restaurant_row(record), place: ::Places::Writer.serialize(record))
      rescue ::Places::Writer::InvalidInput => e
        raise Errors::InvalidArgument, invalid_message(e)
      end

      def self.invalid_message(error)
        base = error.error.tr("_", " ")
        error.values.any? ? "#{base}: #{error.values.join(', ')}" : base
      end
      private_class_method :invalid_message
    end
  end
end
