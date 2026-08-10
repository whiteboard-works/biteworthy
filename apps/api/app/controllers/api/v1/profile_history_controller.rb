module Api
  module V1
    # Phase 4.8 — GET /api/v1/profile/history.
    #
    # The user's recent restaurant visits, newest-first. One row per
    # (user, restaurant, day) — see RecordRestaurantVisitJob. Each
    # entry carries the visible/hidden item counts AT VIEW TIME (the
    # last visit of that day), so a user can see "what I saw" without
    # re-running the filter against current data.
    #
    # Authenticated only — this is private history.
    class ProfileHistoryController < BaseController
      DEFAULT_LIMIT = 30
      MAX_LIMIT     = 100

      def index
        limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        offset = page_offset

        # The third reader that bypasses `Restaurant.published` — like
        # the saved lists it shows unpublished restaurants so the page
        # can grey out the link, so it filters `kept` itself. History is
        # history, but a "recently viewed" link to a 404 is not history,
        # it is a dead end.
        scope = current_user.restaurant_visits
                            .joins(:restaurant).merge(Restaurant.kept)
                            .newest_first
                            .includes(restaurant: :city)
                            .offset(offset)
                            .limit(limit)

        render json: {
          visits: scope.map { |v| serialize(v) },
          total:  current_user.restaurant_visits.count
        }
      end

      private

      def serialize(visit)
        r = visit.restaurant
        {
          id:                  visit.id,
          viewed_on:           visit.viewed_on,
          updated_at:          visit.updated_at,
          items_visible_count: visit.items_visible_count,
          items_hidden_count:  visit.items_hidden_count,
          restaurant: {
            id:   r.id,
            slug: r.slug,
            name: r.name,
            city: { slug: r.city.slug, name: r.city.name, region: r.city.region }
          }
        }
      end
    end
  end
end
