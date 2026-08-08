# frozen_string_literal: true

module Tools
  module History
    class ListVisits < Tools::Base
      audience :user

      tool_name "list_visits"
      title "Restaurants the caller has looked at"
      description <<~TEXT
        The caller's own browsing history — restaurants whose filtered menu
        they opened, newest first, one row per restaurant per day.

        `items_visible_count` and `items_hidden_count` are what they saw AT
        THE TIME, not what the filter would say now. If a user asks "what
        could I eat at that place I looked at last week", use this to find the
        restaurant, then call `get_menu` for current data — do not quote the
        old counts as though they still hold.

        This is private data. Never surface it for anyone but its owner.
      TEXT

      input_schema(
        properties: {
          limit:  { type: "integer", description: "Max rows, 1–100. Default 30." },
          offset: { type: "integer", description: "Rows to skip, for paging." }
        }
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      DEFAULT_LIMIT = 30
      MAX_LIMIT     = 100

      def self.perform(context:, limit: nil, offset: nil)
        user  = context.user!
        scope = user.restaurant_visits
        page  = scope.newest_first
                     .includes(restaurant: :city)
                     .offset(clamp_offset(offset))
                     .limit(clamp_limit(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT))

        ok(visits: page.map { |visit| visit_row(visit) }, total: scope.count)
      end

      def self.visit_row(visit)
        restaurant = visit.restaurant
        {
          viewed_on: visit.viewed_on,
          restaurant: {
            id: restaurant.id, slug: restaurant.slug, name: restaurant.name,
            city: restaurant.city.name
          },
          items_visible_count: visit.items_visible_count,
          items_hidden_count:  visit.items_hidden_count
        }
      end
      private_class_method :visit_row
    end
  end
end
