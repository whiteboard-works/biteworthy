# frozen_string_literal: true

module Tools
  module History
    class ListSaved < Tools::Base
      audience :user

      tool_name "list_saved"
      title "The caller's saved restaurants and dishes"
      description <<~TEXT
        Everything the caller has saved with `save_restaurant` or `save_item`.

        A saved dish is not necessarily one they can still eat — data changes,
        and so do avoid lists. Before telling someone a saved dish is fine for
        them, re-check it with `explain_item`.

        Private data; never surface it for anyone but its owner.
      TEXT

      input_schema(
        properties: {
          kind: {
            type: "string",
            description: "Limit to one kind. Default returns both.",
            enum: %w[restaurants items both]
          },
          limit: { type: "integer", description: "Max rows per kind, 1–100. Default 50." }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      DEFAULT_LIMIT = 50
      MAX_LIMIT     = 100

      def self.perform(context:, kind: "both", limit: nil)
        user = context.user!
        rows = clamp_limit(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT)

        payload = {}
        payload[:restaurants] = saved_restaurants(user, rows) if kind != "items"
        payload[:items]       = saved_items(user, rows)       if kind != "restaurants"
        ok(payload)
      end

      def self.saved_restaurants(user, rows)
        # `.kept` for the same reason as ProfileFavoritesController:
        # this reader shows unpublished restaurants on purpose and so
        # does not inherit the archive filter from `published`.
        user.favorited_restaurants.kept.includes(:city).limit(rows).map do |restaurant|
          {
            id: restaurant.id, slug: restaurant.slug, name: restaurant.name,
            city: restaurant.city.name, status: restaurant.status
          }
        end
      end
      private_class_method :saved_restaurants

      def self.saved_items(user, rows)
        # `.kept` on the dishes half too — otherwise the model reports a
        # saved dish whose restaurant no longer resolves, and
        # `explain_item`, the tool it is told to re-check with, merges
        # `Restaurant.published` and fails.
        user.favorited_items.joins(:restaurant).merge(Restaurant.kept)
            .includes(:restaurant).limit(rows).map do |item|
          {
            id: item.id, name: untrusted(item.name),
            restaurant: { id: item.restaurant_id, slug: item.restaurant.slug, name: item.restaurant.name }
          }
        end
      end
      private_class_method :saved_items
    end
  end
end
