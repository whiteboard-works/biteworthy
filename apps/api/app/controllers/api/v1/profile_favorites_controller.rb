module Api
  module V1
    # GET /api/v1/profile/favorites — the caller's saved restaurants and
    # dishes for the account page, newest first.
    #
    # Returns everything (no pagination) — a favorites list is small and
    # silently capping it would hide saves. Each row carries `status` so
    # the page can skip the link when the restaurant/dish is no longer
    # viewable (the public pages are published-only), same as My reviews.
    #
    # Authenticated only — private data.
    class ProfileFavoritesController < BaseController
      def index
        restaurants = current_user.favorite_restaurants
                                  .includes(:restaurant)
                                  .order(created_at: :desc)
                                  .map { |f| serialize_restaurant(f.restaurant) }

        items = current_user.favorite_items
                            .includes(item: :restaurant)
                            .order(created_at: :desc)
                            .map { |f| serialize_item(f.item) }

        render json: { restaurants: restaurants, items: items }
      end

      private

      def serialize_restaurant(restaurant)
        {
          id:     restaurant.id,
          slug:   restaurant.slug,
          name:   restaurant.name,
          status: restaurant.status
        }
      end

      def serialize_item(item)
        {
          id:     item.id,
          name:   item.name,
          status: item.status,
          restaurant: {
            id:   item.restaurant_id,
            slug: item.restaurant.slug,
            name: item.restaurant.name
          }
        }
      end
    end
  end
end
