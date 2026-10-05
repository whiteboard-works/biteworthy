# frozen_string_literal: true

module Tools
  module Admin
    # Replace a restaurant's weekly hours. Supports multiple intervals per day
    # (lunch + dinner) and validates every time of day before writing.
    class SetRestaurantHours < Tools::AdminBase
      tool_name "set_restaurant_hours"
      title "Set restaurant hours"
      description <<~TEXT
        Replace a restaurant's weekly hours. This is a WHOLESALE replacement —
        the old hours are deleted and the new ones written as one transaction.

        Each row is { day_of_week: 0-6 (Sunday=0), opens_at: "HH:MM",
        closes_at: "HH:MM" }. Multiple intervals per day are fine — lunch
        11:00-14:00 plus dinner 17:00-21:00 is two rows with the same
        day_of_week.

        A day with both fields blank = closed that day. A day with one blank
        and one filled is invalid. A day can be omitted from the list = closed.

        All times are validated as HH:MM (24-hour) before saving.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          hours: {
            type: "array",
            items: {
              type: "object",
              properties: {
                day_of_week: { type: "integer", minimum: 0, maximum: 6 },
                opens_at: { type: "string", pattern: "^([01]\\d|2[0-3]):[0-5]\\d$" },
                closes_at: { type: "string", pattern: "^([01]\\d|2[0-3]):[0-5]\\d$" }
              },
              required: ["day_of_week"]
            },
            description: "Array of hour ranges. Empty array = closed all week."
          }
        },
        required: %w[restaurant hours]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { "Setting hours" }

      def self.perform(context:, restaurant:, hours:)
        context.admin!
        record = find_restaurant!(restaurant)
        Places::Writer.replace_hours!(record, hours)

        ok(Places::Writer.serialize(record))
      rescue Places::Writer::InvalidInput => e
        raise Errors::InvalidArgument, "#{e.error}: #{e.values.join(', ')}"
      end
    end
  end
end
