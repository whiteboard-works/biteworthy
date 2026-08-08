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
    # never did — hitting it 500'd. Capped at 25 rows, name-ordered.
    class RestaurantsController < BaseController
      skip_before_action :authenticate_user!, only: [:show, :index]

      INDEX_LIMIT = 25

      def index
        scope = Restaurant.published.includes(:city, :addresses)
        q = params[:q].to_s.strip
        if q.present?
          scope = scope.where(
            "restaurants.name ILIKE ?",
            "%#{Restaurant.sanitize_sql_like(q)}%"
          )
        end
        restaurants = scope.order(:name).limit(INDEX_LIMIT)
        render json: { restaurants: restaurants.map { |r| serialize_summary(r) } }
      end

      def show
        restaurant = Restaurant.published.includes(:city).find_by_id_or_slug!(params[:id])
        # `favorited` seeds the detail page's save button. Anonymous → false.
        render json: serialize(restaurant).merge(favorited: current_user_favorited_restaurant?(restaurant))
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
          render json: serialize(result.restaurant), status: :created
        end
      rescue ArgumentError
        render json: { error: "name_required" }, status: :unprocessable_entity
      rescue ::Restaurants::Create::UnknownCity
        render json: { error: "unknown_city" }, status: :not_found
      end

      private

      # Lighter than #serialize — list rows don't need claim fields,
      # but the home screen wants an address line + coords (the
      # near-me sort lands with expo-location in a followup).
      def serialize_summary(r)
        first_address = r.addresses.first
        {
          id:     r.id,
          slug:   r.slug,
          name:   r.name,
          status: r.status,
          city:   { slug: r.city.slug, name: r.city.name, region: r.city.region },
          street:    first_address&.street,
          latitude:  first_address&.latitude&.to_f,
          longitude: first_address&.longitude&.to_f
        }
      end

      # Whether the signed-in caller has saved this restaurant (false anonymously).
      def current_user_favorited_restaurant?(restaurant)
        return false unless current_user
        FavoriteRestaurant.exists?(user_id: current_user.id, restaurant_id: restaurant.id)
      end

      def serialize(r)
        {
          id:                 r.id,
          slug:               r.slug,
          name:               r.name,
          about:              r.about,
          phone:              r.phone,
          website:            r.website,
          status:             r.status,
          # Phase 4.9 — non-PII signals so the web page can show or
          # hide the "Claim this restaurant" button without a second
          # roundtrip. claimed_by_user_id is the user's UUID; not
          # private and useful for "is this me" comparisons.
          claimed_at:         r.claimed_at,
          claimed_by_user_id: r.claimed_by_user_id,
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
