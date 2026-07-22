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

      # Calibrated against pg_trgm similarity() on realistic pairs:
      # true duplicates ("Maria's Tacos"/"Marias Taco" 0.53,
      # "Home Slice Pizza"/"Home Slice" 0.65, "Oscar's Cafe"/
      # "Oscars Café" 0.50) sit above 0.45; genuinely different
      # restaurants ("Durango Diner"/"Durango Bagel" 0.42,
      # "Thai Kitchen"/"Himalayan Kitchen" 0.35) sit below. This is a
      # "did you mean?" prompt with a force override, not a hard block,
      # so the cost of a borderline match is one extra tap.
      DUPLICATE_SIMILARITY_THRESHOLD = 0.45
      MAX_DUPLICATE_CANDIDATES       = 5

      def show
        restaurant = Restaurant.published.includes(:city).find_by_id_or_slug!(params[:id])
        # `favorited` seeds the detail page's save button. Anonymous → false.
        render json: serialize(restaurant).merge(favorited: current_user_favorited_restaurant?(restaurant))
      end

      def create
        name = params.require(:name).to_s.strip
        if name.blank?
          render json: { error: "name_required" }, status: :unprocessable_entity
          return
        end

        city = City.find_by(slug: params.require(:city_slug).to_s)
        if city.nil?
          render json: { error: "unknown_city" }, status: :not_found
          return
        end

        unless params[:force].to_s == "true"
          candidates = duplicate_candidates(name, city)
          if candidates.any?
            render json: { error: "possible_duplicate", candidates: candidates },
                   status: :conflict
            return
          end
        end

        restaurant = Restaurant.create!(
          name:               name,
          slug:               unique_slug_for(name),
          city:               city,
          status:             "draft",
          created_by_user_id: current_user.id
        )
        attach_address!(restaurant, city)

        render json: serialize(restaurant), status: :created
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

      def duplicate_candidates(name, city)
        Restaurant
          .where(city: city)
          .where("similarity(restaurants.name, ?) > ?", name, DUPLICATE_SIMILARITY_THRESHOLD)
          .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array(
            ["similarity(restaurants.name, ?) DESC", name]
          )))
          .limit(MAX_DUPLICATE_CANDIDATES)
          .includes(:addresses)
          .map do |r|
            { id: r.id, slug: r.slug, name: r.name, status: r.status,
              street: r.addresses.first&.street }
          end
      end

      # parameterize + numeric suffix on collision ("ninis", "ninis-2").
      def unique_slug_for(name)
        base = name.parameterize
        base = "restaurant" if base.blank?
        return base unless Restaurant.exists?(slug: base)

        n = 2
        n += 1 while Restaurant.exists?(slug: "#{base}-#{n}")
        "#{base}-#{n}"
      end

      def attach_address!(restaurant, city)
        street = params[:street].to_s.strip.presence
        postal = params[:postal_code].to_s.strip.presence
        return if street.nil? && postal.nil?

        restaurant.addresses.create!(
          street:      street,
          postal_code: postal,
          city:        city.name,
          region:      city.region
        )
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
