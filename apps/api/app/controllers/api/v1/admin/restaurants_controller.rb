module Api
  module V1
    module Admin
      # POST /api/v1/admin/restaurants/:id/confirm_community — flips a
      # restaurant's `suggested` human joins to `confirmed` and
      # graduates fully-confirmed items to strict-mode visibility (the
      # web-admin twin of Avo's ConfirmCommunity action; the logic is
      # Restaurant#confirm_community_associations!). Idempotent — a
      # second call updates zero rows. Index/show/update land with the
      # management PR.
      class RestaurantsController < BaseController
        def confirm_community
          restaurant = Restaurant.find(params[:id])
          counts = restaurant.confirm_community_associations!
          render json: { restaurant_id: restaurant.id, confirmed: counts }
        end
      end
    end
  end
end
