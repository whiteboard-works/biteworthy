module Api
  module V1
    module Admin
      # Where a restaurant is and when it's open.
      #
      #   GET  /api/v1/admin/restaurants/:id/place
      #   PUT  /api/v1/admin/restaurants/:id/address
      #   PUT  /api/v1/admin/restaurants/:id/hours
      #
      # Both writes are wholesale replacements rather than CRUD: a
      # restaurant has one address in practice (the schema allows many
      # for future multi-location), and hours are only ever edited as a
      # full week — a per-row API would let a save land half-applied
      # and show the wrong open time.
      #
      # Every field is validated BEFORE it is coerced. Rails' casts are
      # lossy in exactly the directions that hurt here: "monday".to_i is
      # 0 (Sunday), an unparseable time becomes nil (which this API
      # encodes as "closed"), and a non-numeric latitude becomes 0.0
      # (Null Island, which the public restaurant payload then serves).
      # Each of those would be a silent 200 corrupting live data.
      class PlacesController < BaseController
        DAYS      = (0..6).to_a.freeze
        TIME_OF_DAY = /\A([01]\d|2[0-3]):[0-5]\d\z/

        def show
          render json: serialize_place(restaurant)
        end

        def update_address
          attrs = address_attrs
          return if performed?

          address = restaurant.addresses.order(:created_at).first || restaurant.addresses.new
          address.update!(attrs)
          render json: serialize_place(restaurant.reload)
        end

        def update_hours
          rows = params[:hours]
          unless rows.is_a?(Array)
            render json: { error: "hours_must_be_an_array" }, status: :unprocessable_entity
            return
          end

          parsed = parse_hours(rows)
          return if performed?

          restaurant.transaction do
            restaurant.hours.destroy_all
            parsed.each { |row| restaurant.hours.create!(row) }
          end

          render json: serialize_place(restaurant.reload)
        end

        private

        def restaurant
          @restaurant ||= Restaurant.find(params[:id])
        end

        # Returns the parsed rows, or renders a 422 and returns nil.
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

            opens  = parse_time_of_day(row[:opens_at]  || row["opens_at"],  bad_times)
            closes = parse_time_of_day(row[:closes_at] || row["closes_at"], bad_times)

            { day_of_week: day, opens_at: opens, closes_at: closes }
          end

          if bad_rows.any?
            render json: { error: "hour_rows_must_be_objects", values: bad_rows },
                   status: :unprocessable_entity
          elsif bad_days.any?
            render json: { error: "invalid_day_of_week", values: bad_days },
                   status: :unprocessable_entity
          elsif bad_times.any?
            render json: { error: "invalid_time_of_day", values: bad_times },
                   status: :unprocessable_entity
          elsif parsed.map { |row| row[:day_of_week] }.uniq.length != parsed.length
            render json: { error: "duplicate_day_of_week" }, status: :unprocessable_entity
          end

          parsed
        end

        # Blank = closed (what the nullable columns are for). Anything
        # else must look like HH:MM — a typo'd "25:99" silently casting
        # to nil would publish the restaurant as closed that day.
        def parse_time_of_day(value, errors)
          return nil if value.nil? || value.to_s.strip.empty?

          text = value.to_s.strip
          unless text.match?(TIME_OF_DAY)
            errors << text
            return nil
          end
          text
        end

        def address_attrs
          permitted = params.permit(:street, :city, :region, :postal_code, :country,
                                    :map_provider_place_id)
                            .to_h.symbolize_keys

          %i[latitude longitude].each do |field|
            next unless params.key?(field)
            raw = params[field]
            if raw.nil? || raw.to_s.strip.empty?
              permitted[field] = nil
              next
            end

            value = Float(raw, exception: false)
            if value.nil?
              render json: { error: "invalid_coordinate", field: field }, status: :unprocessable_entity
              return {}
            end
            permitted[field] = value
          end

          permitted
        end

        def serialize_place(restaurant)
          address = restaurant.addresses.order(:created_at).first
          {
            restaurant_id: restaurant.id,
            address: address && {
              id:             address.id,
              street:         address.street,
              city:           address.city,
              region:         address.region,
              postal_code:    address.postal_code,
              country:        address.country,
              latitude:       address.latitude&.to_f,
              longitude:      address.longitude&.to_f,
              map_provider_place_id: address.map_provider_place_id
            },
            hours: restaurant.hours.order(:day_of_week).map do |hour|
              {
                id:          hour.id,
                day_of_week: hour.day_of_week,
                opens_at:    hour.opens_at&.strftime("%H:%M"),
                closes_at:   hour.closes_at&.strftime("%H:%M")
              }
            end
          }
        end
      end
    end
  end
end
