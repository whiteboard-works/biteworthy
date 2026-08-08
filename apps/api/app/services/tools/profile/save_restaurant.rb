# frozen_string_literal: true

module Tools
  module Profile
    class SaveRestaurant < Tools::Base
      audience :user

      tool_name "save_restaurant"
      title "Save or unsave a restaurant"
      description <<~TEXT
        Add a restaurant to the caller's saved list, or remove it. Idempotent —
        saving something already saved is a no-op, not an error.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant UUID or slug." },
          saved: {
            type: "boolean",
            description: "true to save (default), false to remove from the saved list."
          }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, restaurant:, saved: true)
        user   = context.user!
        record = Restaurant.published.find_by_id_or_slug!(restaurant)

        if saved
          FavoriteRestaurant.find_or_create_by!(user_id: user.id, restaurant_id: record.id)
        else
          FavoriteRestaurant.where(user_id: user.id, restaurant_id: record.id).destroy_all
        end

        ok(restaurant: { id: record.id, slug: record.slug, name: record.name }, saved: saved)
      end
    end
  end
end
