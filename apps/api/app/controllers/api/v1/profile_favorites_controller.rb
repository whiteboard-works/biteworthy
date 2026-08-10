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
        # This list deliberately shows draft/closed restaurants so the
        # page can grey out the link — but an archived one is gone from
        # the product, and a bookmark to it would 404 with no
        # explanation. `Restaurant.published` (the archive chokepoint)
        # is bypassed here on purpose, so the filter is explicit.
        restaurants = current_user.favorite_restaurants
                                  .joins(:restaurant).merge(Restaurant.kept)
                                  .includes(:restaurant)
                                  .order(created_at: :desc)
                                  .map { |f| serialize_restaurant(f.restaurant) }

        # Same filter on the dishes half. A saved dish at an archived
        # restaurant would otherwise come back reporting
        # `status: "published"` — archiving does not touch `status` —
        # so the page renders a live link to a page that 404s.
        items = current_user.favorite_items
                            .joins(item: :restaurant).merge(Restaurant.kept)
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
            id:     item.restaurant_id,
            slug:   item.restaurant.slug,
            name:   item.restaurant.name,
            # The dish page is published-only AND resolves through the
            # restaurant, so the web needs the restaurant's status too to
            # decide whether the dish link is safe (a dish stays
            # 'published' when its restaurant is later closed/unpublished).
            status: item.restaurant.status
          }
        }
      end
    end
  end
end
