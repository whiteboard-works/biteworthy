module Api
  module V1
    module Admin
      # Where a restaurant is and when it's open.
      #
      #   GET  /api/v1/admin/restaurants/:id/place
      #   PUT  /api/v1/admin/restaurants/:id/address
      #   PUT  /api/v1/admin/restaurants/:id/hours
      #
      # Validation and the wholesale-replace semantics live in
      # ::Places::Writer (root-scoped — a bare `Places::` here would
      # resolve under Api::V1::Admin), shared with the MCP `edit_place`
      # tool. This controller is the HTTP adapter: it turns the writer's
      # InvalidInput into the 422 shape the admin UI already handles.
      class PlacesController < BaseController
        def show
          render json: ::Places::Writer.serialize(restaurant)
        end

        def update_address
          updated = ::Places::Writer.replace_address!(restaurant, address_params)
          render json: ::Places::Writer.serialize(updated)
        end

        def update_hours
          updated = ::Places::Writer.replace_hours!(restaurant, hour_rows)
          render json: ::Places::Writer.serialize(updated)
        end

        private

        def restaurant
          @restaurant ||= Restaurant.find(params[:id])
        end

        def address_params
          params.permit(:street, :city, :region, :postal_code, :country,
                        :map_provider_place_id, :latitude, :longitude)
                .to_h.symbolize_keys
        end

        # `permit!`-free: the rows are read field by field by the writer,
        # which validates each before coercing it.
        def hour_rows
          rows = params[:hours]
          return rows unless rows.is_a?(Array)

          rows.map { |row| row.is_a?(ActionController::Parameters) ? row.to_unsafe_h : row }
        end

        rescue_from ::Places::Writer::InvalidInput do |error|
          payload = { error: error.error }
          payload[:values] = error.values if error.values.any?
          payload[:field]  = error.values.first if error.error == "invalid_coordinate"
          render json: payload, status: :unprocessable_entity
        end
      end
    end
  end
end
