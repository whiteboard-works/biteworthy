module Api
  module V1
    # Phase 4.2 — POST /api/v1/items/:id/never_hide marks an item as
    # "always shown for me" for the authenticated user. DELETE removes
    # the override. Both are idempotent.
    #
    # `current_user.profile` still drives the default filter; this just
    # opts out of the hide step for one specific item.
    class ItemOverridesController < BaseController
      before_action :load_item

      def create
        UserItemOverride.find_or_create_by!(user: current_user, item: @item) do |o|
          o.never_hide = true
        end
        render json: serialize_override(true), status: :ok
      rescue ActiveRecord::RecordNotUnique
        # Same reasoning as FavoriteItems: a concurrent double-tap loses
        # the race to the unique index, but the override exists either
        # way, so the caller got what they asked for. Declared here
        # because the inherited handler answers 422, which is the right
        # default and the wrong answer for an idempotent endpoint.
        render json: serialize_override(true), status: :ok
      end

      def destroy
        UserItemOverride.where(user: current_user, item: @item).destroy_all
        render json: serialize_override(false), status: :ok
      end

      private

      def load_item
        @item = Item.published.find(params[:id])
      end

      def serialize_override(active)
        { item_id: @item.id, overridden_by_user: active }
      end
    end
  end
end
