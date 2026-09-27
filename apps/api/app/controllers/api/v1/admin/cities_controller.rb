module Api
  module V1
    module Admin
      # POST /api/v1/admin/cities — add a city. Admin-only because a city
      # is public coverage: its slug goes into every restaurant URL there.
      # The rules live in ::Cities::Create, shared with `create_city`.
      class CitiesController < BaseController
        def create
          city = ::Cities::Create.call(name: params.require(:name), region: params.require(:region))
          render json: city.summary, status: :created
        rescue ::Cities::Create::Duplicate => e
          render json: { error: "city_exists", city: e.city.summary }, status: :conflict
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
