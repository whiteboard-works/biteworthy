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
      class PlacesController < BaseController
        DAYS = (0..6).to_a.freeze

        def show
          restaurant = Restaurant.find(params[:id])
          render json: serialize_place(restaurant)
        end

        def update_address
          restaurant = Restaurant.find(params[:id])
          address = restaurant.addresses.first || restaurant.addresses.new
          address.update!(address_params)
          render json: serialize_place(restaurant.reload)
        end

        def update_hours
          restaurant = Restaurant.find(params[:id])
          rows = params[:hours]
          unless rows.is_a?(Array)
            render json: { error: "hours_must_be_an_array" }, status: :unprocessable_entity
            return
          end

          parsed = rows.filter_map { |row| parse_hour_row(row) }
          bad_days = parsed.map { |row| row[:day_of_week] } - DAYS
          if bad_days.any?
            render json: { error: "invalid_day_of_week", values: bad_days },
                   status: :unprocessable_entity
            return
          end

          restaurant.transaction do
            restaurant.hours.destroy_all
            parsed.each { |row| restaurant.hours.create!(row) }
          end

          render json: serialize_place(restaurant.reload)
        end

        private

        def parse_hour_row(row)
          return nil unless row.respond_to?(:[])
          day = row[:day_of_week] || row["day_of_week"]
          return nil if day.nil?

          {
            day_of_week: day.to_i,
            # Blank times mean "closed that day" — the column is
            # nullable precisely for that.
            opens_at:  (row[:opens_at] || row["opens_at"]).presence,
            closes_at: (row[:closes_at] || row["closes_at"]).presence
          }
        end

        def address_params
          params.permit(:street, :city, :region, :postal_code, :country,
                        :latitude, :longitude, :map_provider_place_id)
                .to_h.symbolize_keys
        end

        def serialize_place(restaurant)
          address = restaurant.addresses.first
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
