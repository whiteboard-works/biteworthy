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
          # `.community`, not `.community_published`: the latter carries
          # `kept` through `published`, which would contradict the
          # archived filter above and return nothing.
          if params[:filter].to_s == "community_published"
            scope = scope.where(status: "published").community
          end
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
            render_archived(restaurant, serialize_restaurant(restaurant))
          end
        end

        def restore
          restaurant = Restaurant.find(params[:id])
          restaurant.update!(archived_at: nil)
          render json: serialize_restaurant(restaurant)
        end

        # POST /api/v1/admin/restaurants/:id/backfill_structure — rebuild
        # menu sections and item variants from accepted ingestion payloads.
        def backfill_structure
          restaurant = Restaurant.find(params[:id])
          dry_run    = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false

          result = Restaurants::BackfillStructure.new(
            restaurant: restaurant,
            dry_run:    dry_run
          ).call

          render json: {
            restaurant_id:     restaurant.id,
            dry_run:           dry_run,
            sections_created:  result[:sections_created],
            variants_added:    result[:variants_added]
          }
        end

        # POST /api/v1/admin/restaurants/:id/backfill_confidence — rewrite
        # source and confidence for published items from accepted ingestion payloads.
        # Defaults to dry_run=true for safety.
        def backfill_confidence
          restaurant = Restaurant.find(params[:id])
          # Default to true for safety — must explicitly pass dry_run=false to apply changes
          dry_run = params.key?(:dry_run) ? ActiveModel::Type::Boolean.new.cast(params[:dry_run]) : true

          result = ::Admin::BackfillConfidence.call(restaurant: restaurant, dry_run: dry_run)

          render json: result
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
