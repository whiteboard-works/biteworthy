module Api
  module V1
    module Admin
      # Restaurant management for the web admin.
      #
      #   GET   /api/v1/admin/restaurants           list/search
      #   GET   /api/v1/admin/restaurants/:id       detail + confidence counts
      #   PATCH /api/v1/admin/restaurants/:id       edit + status (publish/unpublish/close)
      #   POST  /api/v1/admin/restaurants/:id/confirm_community
      #   POST  /api/v1/admin/restaurants/:id/restore
      #   DEL   /api/v1/admin/restaurants/:id        archive (or ?hard=true)
      #
      # Slug is immutable in v1 — it's the SEO URL and the
      # find_by_id_or_slug! lookup key. Status writes go through the
      # model's inclusion validation (draft|published|closed).
      class RestaurantsController < BaseController
        include Deletable

        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        def index
          scope = Restaurant.order(created_at: :desc).includes(:city)
          # Archived rows are hidden from the list by default but stay
          # reachable, because an admin who archives the wrong
          # restaurant needs a way to find it again.
          scope = params[:archived].to_s == "true" ? scope.archived : scope.kept
          scope = scope.where(status: params[:status]) if Restaurant::STATUSES.include?(params[:status].to_s)
          scope = scope.community_published if params[:filter].to_s == "community_published"
          scope = scope.where(city_id: params[:city_id]) if params[:city_id].present?

          if params[:q].present?
            q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where("restaurants.name ILIKE :q", q: q)
          end

          total  = scope.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset
          page   = scope.limit(limit).offset(offset).to_a

          item_counts      = Item.where(restaurant_id: page.map(&:id)).group(:restaurant_id).count
          suggested_counts = Item.where(restaurant_id: page.map(&:id), confidence: "suggested")
                                 .group(:restaurant_id).count

          render json: {
            restaurants: page.map do |r|
              serialize_restaurant(r).merge(
                items_count:           item_counts[r.id] || 0,
                # The "needs strict-mode graduation" signal.
                suggested_items_count: suggested_counts[r.id] || 0
              )
            end,
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def show
          restaurant = Restaurant.find(params[:id])
          render json: serialize_restaurant(restaurant).merge(
            about:      restaurant.about,
            website:    restaurant.website,
            phone:      restaurant.phone,
            claimed_at: restaurant.claimed_at,
            items_by_confidence: Item.where(restaurant_id: restaurant.id)
                                     .group(:confidence).count
          )
        end

        def update
          restaurant = Restaurant.find(params[:id])
          if params.key?(:slug) && params[:slug].to_s != restaurant.slug
            render json: { error: "immutable_field", fields: ["slug"] },
                   status: :unprocessable_entity
            return
          end

          attrs = {}
          %i[name about website phone status].each do |field|
            next unless params.key?(field)
            # Scalar-only: a nested hash param would otherwise be
            # stringified into the column by the type cast.
            value = params[field]
            attrs[field] = value if value.nil? || value.is_a?(String)
          end
          restaurant.update!(attrs)

          render json: serialize_restaurant(restaurant)
        end

        def confirm_community
          restaurant = Restaurant.find(params[:id])
          counts = restaurant.confirm_community_associations!
          render json: { restaurant_id: restaurant.id, confirmed: counts }
        end

        # A hard delete here is the widest one in the app: `dependent:
        # :destroy` takes the menus, sections, items, addresses, hours
        # and everyone's saved-restaurant rows with it. That is the
        # reason it is gated on super admin and the reason the web asks
        # for the name to be typed.
        def destroy
          authorize_hard_delete! or return
          restaurant = Restaurant.find(params[:id])

          if hard_delete_requested?
            restaurant.destroy!
            render_hard_deleted(restaurant)
          else
            restaurant.update!(archived_at: Time.current)
            render json: serialize_restaurant(restaurant)
          end
        end

        def restore
          restaurant = Restaurant.find(params[:id])
          restaurant.update!(archived_at: nil)
          render json: serialize_restaurant(restaurant)
        end

        private

        def serialize_restaurant(restaurant)
          {
            id:     restaurant.id,
            slug:   restaurant.slug,
            name:   restaurant.name,
            status: restaurant.status,
            archived_at: restaurant.archived_at,
            city: restaurant.city && { id: restaurant.city.id, name: restaurant.city.name },
            created_by_user_id: restaurant.created_by_user_id,
            claimed_by_user_id: restaurant.claimed_by_user_id,
            created_at: restaurant.created_at
          }
        end
      end
    end
  end
end
