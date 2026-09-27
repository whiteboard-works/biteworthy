module Api
  module V1
    # GET /api/v1/cities — every city we cover, including ones with no
    # published restaurants yet. The "add a restaurant" form picks its
    # city from this; the restaurant list can't supply a brand-new city.
    class CitiesController < BaseController
      skip_before_action :authenticate_user!, only: [ :index ]

      def index
        render json: { cities: City.order(:name).map(&:summary) }
      end
    end
  end
end
