# frozen_string_literal: true

# Where a restaurant is and when it's open.
#
# Extracted from Api::V1::Admin::PlacesController so the MCP `edit_place`
# tool and the REST endpoint validate identically. Every field is checked
# BEFORE it is coerced, because Rails' casts are lossy in exactly the
# directions that hurt here: `"monday".to_i` is 0 (Sunday), an
# unparseable time becomes nil (which this API encodes as "closed"), and
# a non-numeric latitude becomes 0.0 — Null Island, which the public
# restaurant payload then serves.
#
# Both writes are wholesale replacements rather than CRUD: a restaurant
# has one address in practice, and hours are only ever edited as a full
# week, so a per-row API would let a save land half-applied and advertise
# the wrong open time.
module Places
  class Writer
    class InvalidInput < StandardError
      attr_reader :error, :values

      def initialize(error, values = [])
        @error  = error
        @values = values
        super(error)
      end
    end

    DAYS        = (0..6).to_a.freeze
    TIME_OF_DAY = /\A([01]\d|2[0-3]):[0-5]\d\z/
    ADDRESS_FIELDS = %i[street city region postal_code country map_provider_place_id].freeze

    class << self
      def replace_address!(restaurant, attrs)
        address = restaurant.addresses.order(:created_at).first || restaurant.addresses.new
        address.update!(address_attrs(attrs))
        restaurant.reload
      end

      def replace_hours!(restaurant, rows)
        raise InvalidInput, "hours_must_be_an_array" unless rows.is_a?(Array)

        parsed = parse_hours(rows)
        restaurant.transaction do
          restaurant.hours.destroy_all
          parsed.each { |row| restaurant.hours.create!(row) }
        end
        restaurant.reload
      end

      def serialize(restaurant)
        address = restaurant.addresses.order(:created_at).first
        {
          restaurant_id: restaurant.id,
          address: address && {
            id:                    address.id,
            street:                address.street,
            city:                  address.city,
            region:                address.region,
            postal_code:           address.postal_code,
            country:               address.country,
            latitude:              address.latitude&.to_f,
            longitude:             address.longitude&.to_f,
            map_provider_place_id: address.map_provider_place_id
          },
          # Split shifts come back in the order they're worked.
          hours: restaurant.hours.order(:day_of_week, :opens_at).map do |hour|
            {
              id:          hour.id,
              day_of_week: hour.day_of_week,
              opens_at:    hour.opens_at&.strftime("%H:%M"),
              closes_at:   hour.closes_at&.strftime("%H:%M")
            }
          end
        }
      end

      def address_attrs(attrs)
        permitted = attrs.symbolize_keys.slice(*ADDRESS_FIELDS)

        %i[latitude longitude].each do |field|
          next unless attrs.key?(field) || attrs.key?(field.to_s)
          raw = attrs[field] || attrs[field.to_s]
          if raw.nil? || raw.to_s.strip.empty?
            permitted[field] = nil
            next
          end

          value = Float(raw, exception: false)
          raise InvalidInput.new("invalid_coordinate", [field.to_s]) if value.nil?
          permitted[field] = value
        end

        permitted
      end

      # Returns the parsed rows, or raises InvalidInput naming the offenders.
      def parse_hours(rows)
        bad_rows  = []
        bad_days  = []
        bad_times = []

        parsed = rows.filter_map do |row|
          unless row.is_a?(Hash) || row.is_a?(ActionController::Parameters)
            bad_rows << row.to_s
            next
          end

          day = Integer(row[:day_of_week] || row["day_of_week"], exception: false)
          if day.nil? || DAYS.exclude?(day)
            bad_days << (row[:day_of_week] || row["day_of_week"]).to_s
            next
          end

          {
            day_of_week: day,
            opens_at:    parse_time_of_day(row[:opens_at]  || row["opens_at"],  bad_times),
            closes_at:   parse_time_of_day(row[:closes_at] || row["closes_at"], bad_times)
          }
        end

        raise InvalidInput.new("hour_rows_must_be_objects", bad_rows) if bad_rows.any?
        raise InvalidInput.new("invalid_day_of_week", bad_days)       if bad_days.any?
        raise InvalidInput.new("invalid_time_of_day", bad_times)      if bad_times.any?

        mixed = contradictory_days(parsed)
        raise InvalidInput.new("closed_day_has_hours", mixed) if mixed.any?

        # Two identical rows for one day say nothing extra.
        parsed.uniq
      end

      private

      # A day may carry SEVERAL ranges — lunch 11–14, dinner 17–21 is an
      # ordinary restaurant week, and collapsing it to 11–21 would
      # advertise hours the kitchen isn't open. What it may not carry is a
      # blank "closed" row alongside a real range: the two say opposite
      # things and nothing downstream could pick a winner.
      def contradictory_days(parsed)
        parsed.group_by { |row| row[:day_of_week] }
              .select { |_day, rows| rows.any? { |r| closed_row?(r) } && !rows.all? { |r| closed_row?(r) } }
              .keys.map(&:to_s)
      end

      # Blank both ends = "closed that day".
      def closed_row?(row)
        row[:opens_at].nil? && row[:closes_at].nil?
      end

      # Blank = closed (what the nullable columns are for). Anything else
      # must look like HH:MM — a typo'd "25:99" silently casting to nil
      # would publish the restaurant as closed that day.
      def parse_time_of_day(value, errors)
        return nil if value.nil? || value.to_s.strip.empty?

        text = value.to_s.strip
        unless text.match?(TIME_OF_DAY)
          errors << text
          return nil
        end
        text
      end
    end
  end
end
