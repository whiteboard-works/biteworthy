module Api
  module V1
    module Admin
      # Item management for the web admin.
      #
      #   GET   /api/v1/admin/restaurants/:restaurant_id/items — ALL
      #     statuses (the public endpoint filters to published).
      #   PATCH /api/v1/admin/items/:id — name / description / status.
      #     `status: "removed"` is the admin unpublish — the first real
      #     writer of that lifecycle value.
      #
      # Deliberately NOT editable here: `confidence` (transitions stay
      # on the promote!/confirm_community rails — strict-mode safety)
      # and the denormalized ingredient_ids/tag_ids arrays (join
      # callbacks own them).
      class ItemsController < BaseController
        DEFAULT_LIMIT = 50
        MAX_LIMIT     = 200

        def index
          restaurant = Restaurant.find(params[:restaurant_id])
          scope = Item.where(restaurant_id: restaurant.id)
                      .order(:menu_section_id, :name)
                      .includes(:item_variants)
          scope = scope.where(status: params[:status]) if Item::STATUSES.include?(params[:status].to_s)

          total  = scope.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset

          render json: {
            items: scope.limit(limit).offset(offset).map { |item| serialize_item(item) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def update
          item = Item.find(params[:id])

          attrs = {}
          attrs[:name]        = params[:name] if params.key?(:name)
          attrs[:description] = params[:description] if params.key?(:description)
          if params.key?(:status)
            unless Item::STATUSES.include?(params[:status].to_s)
              render json: { error: "invalid_status", allowed: Item::STATUSES },
                     status: :unprocessable_entity
              return
            end
            attrs[:status] = params[:status].to_s
          end
          item.update!(attrs)

          render json: serialize_item(item)
        end

        private

        def serialize_item(item)
          {
            id:               item.id,
            restaurant_id:    item.restaurant_id,
            name:             item.name,
            description:      item.description,
            status:           item.status,
            confidence:       item.confidence,
            popularity:       item.popularity,
            ingredient_count: item.ingredient_ids.size,
            tag_count:        item.tag_ids.size,
            variants: item.item_variants.sort_by { |v| v.position.to_i }.map do |v|
              { size: v.size, price_cents: v.price_cents }
            end,
            created_at: item.created_at
          }
        end
      end
    end
  end
end
