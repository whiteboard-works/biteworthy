module Api
  module V1
    # GET /api/v1/restaurants/:id
    #
    # Phase 3.3 — the mobile (and later web) restaurant page header
    # needs the restaurant's name + city to render. The items endpoint
    # only returns `restaurant_id`; without this the page can't show
    # "Ninis Taqueria · Durango, CO" above the filtered menu.
    #
    # Public (unauthenticated) — anonymous browsing is part of the
    # Phase 3 demo.
    class RestaurantsController < BaseController
      skip_before_action :authenticate_user!, only: [:show]

      def show
        restaurant = Restaurant.published.includes(:city).find(params[:id])
        render json: serialize(restaurant)
      end

      private

      def serialize(r)
        {
          id:      r.id,
          slug:    r.slug,
          name:    r.name,
          about:   r.about,
          phone:   r.phone,
          website: r.website,
          status:  r.status,
          city: {
            id:     r.city.id,
            slug:   r.city.slug,
            name:   r.city.name,
            region: r.city.region
          }
        }
      end
    end
  end
end
