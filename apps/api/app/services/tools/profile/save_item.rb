# frozen_string_literal: true

module Tools
  module Profile
    class SaveItem < Tools::Base
      audience :user

      tool_name "save_item"
      title "Save or unsave a dish"
      description <<~TEXT
        Add a dish to the caller's saved list, or remove it. Take the dish id
        from `get_menu` or `explain_item`. Idempotent.
      TEXT

      input_schema(
        properties: {
          item_id: { type: "string", description: "The dish's UUID." },
          saved: {
            type: "boolean",
            description: "true to save (default), false to remove from the saved list."
          }
        },
        required: ["item_id"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, item_id:, saved: true)
        user = context.user!
        item = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)

        if saved
          FavoriteItem.find_or_create_by!(user_id: user.id, item_id: item.id)
        else
          FavoriteItem.where(user_id: user.id, item_id: item.id).destroy_all
        end

        ok(item: { id: item.id, name: untrusted(item.name) }, saved: saved)
      end
    end
  end
end
