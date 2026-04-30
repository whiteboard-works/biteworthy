module Api
  module V1
    # GET /api/v1/cities/:city_slug/restaurants?profile=:diet_slug
    #
    # Phase 5.6 — backs the SSR `/durango/[diet]` SEO pages. Returns
    # the city's published restaurants ranked by how many items pass
    # the given dietary preset's filter (visible_count DESC, then
    # name ASC).
    #
    # Public + unauthenticated. The endpoint is anonymous-friendly
    # because the SEO landing pages have to render for crawlers + new
    # visitors who haven't signed up.
    #
    # 404s on:
    #   * unknown city slug
    #   * unknown diet slug
    #
    # Empty `restaurants` array is normal (city has no published
    # restaurants yet — Phase 5.7's seed run populates it).
    class CityRestaurantsController < BaseController
      skip_before_action :authenticate_user!, only: [:index]

      def index
        city    = City.find_by!(slug: params[:city_slug])
        profile = DietaryProfile
          .includes(:dietary_profile_ingredients, :dietary_profile_tags)
          .find_by!(slug: params[:profile])

        ranked = Cities::RestaurantRanking.new(city: city, dietary_profile: profile).call

        render json: {
          city:    serialize_city(city),
          profile: serialize_profile(profile),
          restaurants: ranked.map { |r| serialize_ranked(r) }
        }
      end

      private

      def serialize_city(city)
        { id: city.id, slug: city.slug, name: city.name, region: city.region }
      end

      def serialize_profile(profile)
        { id: profile.id, slug: profile.slug, name: profile.name, description: profile.description }
      end

      def serialize_ranked(r)
        {
          id:            r.restaurant.id,
          slug:          r.restaurant.slug,
          name:          r.restaurant.name,
          visible_count: r.visible_count,
          hidden_count:  r.hidden_count,
          total_count:   r.total_count
        }
      end
    end
  end
end
