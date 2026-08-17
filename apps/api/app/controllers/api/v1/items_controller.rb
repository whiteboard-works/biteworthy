module Api
  module V1
    # GET /api/v1/restaurants/:restaurant_id/items
    #
    # Returns every published item at the given restaurant, with each
    # item carrying a per-item filter status + reasons[] array. The UI
    # uses `status: "hidden"` to grey-out an item and renders the
    # reasons inline (e.g., "Hidden — contains dairy (Cheddar)").
    #
    # Filter source:
    #   ?profile=<dietary_profile_slug>  → use that preset's avoid lists
    #   ?strictness=relaxed|balanced|strict → strict-mode toggle
    #   no params + signed-in user → use current_user.profile
    #   no params + anonymous → no filtering (everything visible)
    #
    # The filtering and serialization live in Menus::Filter /
    # Menus::Query so the `get_menu` MCP tool answers identically —
    # this controller is the HTTP adapter, nothing more.
    #
    # The endpoint is intentionally unauthenticated — Phase 3 mobile
    # users browse menus before they create an account.
    class ItemsController < BaseController
      skip_before_action :authenticate_user!, only: [:index, :show]

      rescue_from ProfileToken::InvalidTokenError do |e|
        render json: { error: "Invalid profile_token: #{e.message}" }, status: :unprocessable_entity
      end

      def index
        restaurant = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id])
        payload    = query_for(restaurant).call

        # Phase 4.8 — record an authenticated user's visit to this
        # restaurant for the History tab. Best-effort, async, never
        # blocks the response. Only when the menu was filtered as *them*:
        # a ?profile= / ?profile_token= view would overwrite the day's
        # row (last-write-wins upsert) with counts their own filter never
        # produced.
        if current_user && params[:profile].blank? && params[:profile_token].blank?
          record_visit_for_history(restaurant, payload[:items])
        end

        render json: payload
      end

      def show
        restaurant = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id])
        item       = restaurant.items.published
                               .includes(photo_attachment: :blob,
                                         item_ingredients: :ingredient, item_tags: :tag)
                               .find(params[:id])
        payload    = query_for(restaurant).serialize_one(item)

        # `favorited` seeds the detail page's save button. Anonymous → false.
        render json: payload.merge(favorited: current_user_favorited_item?(item))
      end

      private

      def query_for(restaurant)
        Menus::Query.new(
          restaurant:  restaurant,
          filter:      build_filter,
          user:        current_user,
          public_host: public_host
        )
      end

      def build_filter
        Menus::Filter.build(
          user:          current_user,
          profile_token: params[:profile_token],
          preset_slug:   params[:profile],
          strictness:    params[:strictness]
        )
      end

      # Phase 4.8 — fire-and-forget enqueue. Never raises into the
      # request even if SolidQueue is briefly unhealthy.
      def record_visit_for_history(restaurant, rendered_items)
        visible_count = rendered_items.count { |i| i[:status] == "visible" }
        hidden_count  = rendered_items.size - visible_count
        RecordRestaurantVisitJob.perform_later(
          current_user.id,
          restaurant.id,
          visible_count,
          hidden_count,
          Date.current.iso8601
        )
      rescue StandardError => e
        Rails.logger.warn("RecordRestaurantVisitJob enqueue failed: #{e.class} #{e.message}")
      end

      # Whether the signed-in caller has saved this dish (false anonymously).
      def current_user_favorited_item?(item)
        return false unless current_user
        FavoriteItem.exists?(user_id: current_user.id, item_id: item.id)
      end
    end
  end
end
