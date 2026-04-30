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
