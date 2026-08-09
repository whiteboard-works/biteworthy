module Api
  module V1
    # POST/DELETE /api/v1/items/:id/favorite — toggle a saved dish for
    # the current user. Mirror of FavoriteRestaurantsController.
    class FavoriteItemsController < BaseController
      before_action :load_item

      def create
        FavoriteItem.find_or_create_by!(user: current_user, item: @item)
        render json: serialize(true), status: :ok
      rescue ActiveRecord::RecordNotUnique
        # Deliberately narrower than the inherited 422: saving a dish is
        # idempotent, so losing the race to the unique index means the
        # favorite already exists and the caller got what they asked for.
        render json: serialize(true), status: :ok
      end

      def destroy
        FavoriteItem.where(user: current_user, item: @item).destroy_all
        render json: serialize(false), status: :ok
      end

      private

      def load_item
        @item = Item.published.find(params[:id])
      end

      def serialize(active)
        { item_id: @item.id, favorited: active }
      end
    end
  end
end
