module Api
  module V1
    # PATCH /api/v1/restaurants/:restaurant_id/branding
    #
    # A restaurant's logo and banner, set by its verified owner or an
    # admin. Multipart: `logo` / `banner` files, `remove_logo` /
    # `remove_banner` flags. Answers with the same payload as the public
    # `#show`, so the page can re-render from the response.
    #
    # Looks up `kept` rather than `published`: an admin brands a draft
    # before it goes live, and an owner can only hold a claim on a
    # published restaurant anyway.
    class RestaurantBrandingsController < BaseController
      include RestaurantPayload

      def update
        restaurant = Restaurant.kept.includes(:city, :addresses, :hours).find_by_id_or_slug!(params[:restaurant_id])
        ::Restaurants::Branding.authorize!(current_user, restaurant)

        ::Restaurants::Branding.apply!(
          restaurant,
          logo:          file_param(:logo),
          banner:        file_param(:banner),
          remove_logo:   flag?(:remove_logo),
          remove_banner: flag?(:remove_banner)
        )

        render json: restaurant_payload(restaurant)
                       .merge(favorited: FavoriteRestaurant.exists?(user_id: current_user.id, restaurant_id: restaurant.id))
      rescue ::Restaurants::Branding::Forbidden => e
        render json: { error: e.message }, status: :forbidden
      rescue Images::StripMetadata::Unprocessable => e
        render json: { error: e.message, code: e.code }, status: :unprocessable_entity
      end

      private

      # Only a real upload counts; a string in the field is ignored rather
      # than stringified into an attachment.
      def file_param(name)
        value = params[name]
        value if value.respond_to?(:tempfile)
      end

      def flag?(name)
        ActiveModel::Type::Boolean.new.cast(params[name]) == true
      end
    end
  end
end
