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
    #
    # POST /api/v1/restaurants (Phase 6.2) — the community "scan a new
    # restaurant" entrypoint. Authenticated. Creates a `draft`
    # restaurant recording the creator; a pg_trgm similarity guard
    # answers "did you mean…?" with 409 + candidates before creating a
    # near-duplicate in the same city. `force: true` (sent after the
    # client has shown the candidates) skips the guard.
    # GET /api/v1/restaurants (Phase 7.2) — public list/search backing
    # the mobile home screen. `?q=` is a case-insensitive substring
    # match on name. The route existed since Phase 0 but the action
    # never did — hitting it 500'd. Capped at 100 rows, name-ordered:
    # the launch gate seeds 30 restaurants and the web browse page (and
    # its local name search) treats this response as the complete
    # published list, so the cap must stay comfortably above the real
    # count until pagination exists.
    class RestaurantsController < BaseController
      include RestaurantPayload

      skip_before_action :authenticate_user!, only: [:show, :index]

      INDEX_LIMIT = 100

      def index
        scope = Restaurant.published.includes(:city, :addresses, :hours, logo_attachment: :blob)
        q = params[:q].to_s.strip
        if q.present?
          scope = scope.where(
            "restaurants.name ILIKE ?",
            "%#{Restaurant.sanitize_sql_like(q)}%"
          )
        end
        restaurants = scope.order(:name).limit(INDEX_LIMIT)
        render json: { restaurants: restaurants.map { |r| restaurant_summary_payload(r) } }
      end

      def show
        restaurant = Restaurant.published
                               .includes(:city, :addresses, :hours, logo_attachment: :blob, banner_attachment: :blob)
                               .find_by_id_or_slug!(params[:id])
        # `favorited` seeds the detail page's save button. Anonymous → false.
        render json: restaurant_payload(restaurant).merge(favorited: current_user_favorited_restaurant?(restaurant))
      end

      def create
        result = ::Restaurants::Create.call(
          name:        params.require(:name),
          city_slug:   params.require(:city_slug),
          creator:     current_user,
          street:      params[:street],
          postal_code: params[:postal_code],
          force:       params[:force].to_s == "true"
        )

        if result.duplicate?
          render json: { error: "possible_duplicate", candidates: result.candidates }, status: :conflict
        else
          render json: restaurant_payload(result.restaurant), status: :created
        end
      rescue ArgumentError
        render json: { error: "name_required" }, status: :unprocessable_entity
      rescue ::Restaurants::Create::UnknownCity
        render json: { error: "unknown_city" }, status: :not_found
      end

      private

      # Whether the signed-in caller has saved this restaurant (false anonymously).
      def current_user_favorited_restaurant?(restaurant)
        return false unless current_user
        FavoriteRestaurant.exists?(user_id: current_user.id, restaurant_id: restaurant.id)
      end
    end
  end
end
