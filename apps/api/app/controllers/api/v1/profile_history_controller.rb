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
        limit  = (params[:limit].presence  || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        offset = (params[:offset].presence || 0).to_i.clamp(0, 10_000)

        scope = current_user.restaurant_visits
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
