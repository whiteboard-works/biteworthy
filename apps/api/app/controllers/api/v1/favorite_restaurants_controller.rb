module Api
  module V1
    # POST/DELETE /api/v1/restaurants/:restaurant_id/favorite — toggle a
    # saved restaurant for the current user. Mirrors
    # ItemOverridesController: create is idempotent (find_or_create_by!),
    # destroy is a no-op when absent (where...destroy_all), both echo the
    # resulting favorited state at 200. Auth + 404 come from BaseController.
    class FavoriteRestaurantsController < BaseController
      before_action :load_restaurant

      def create
        FavoriteRestaurant.find_or_create_by!(user: current_user, restaurant: @restaurant)
        render json: serialize(true), status: :ok
      end

      def destroy
        FavoriteRestaurant.where(user: current_user, restaurant: @restaurant).destroy_all
        render json: serialize(false), status: :ok
      end

      private

      def load_restaurant
        @restaurant = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id])
      end

      def serialize(active)
        { restaurant_id: @restaurant.id, favorited: active }
      end
    end
  end
end
