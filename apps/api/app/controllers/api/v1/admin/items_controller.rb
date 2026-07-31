module Api
  module V1
    module Admin
      # Item management for the web admin.
      #
      #   GET   /api/v1/admin/restaurants/:restaurant_id/items — ALL
      #     statuses (the public endpoint filters to published).
      #   PATCH /api/v1/admin/items/:id — name / description / status,
      #     plus the deep edits an admin needs to fix a live dish:
      #     ingredient_slugs / tag_slugs (join sync), variants,
      #     modifiers, and menu_section_id. `status: "removed"` is the
      #     admin unpublish.
      #
      # The write rules live in ::Admin::ItemEditor (root-scoped — a bare
      # `Admin::` here would resolve to Api::V1::Admin). Deliberately NOT
      # editable here: `confidence` (transitions stay on the
      # promote!/confirm_community rails — strict-mode safety) and the
      # denormalized ingredient_ids/tag_ids arrays (join callbacks own
      # them; edits go through the slug lists instead).
      class ItemsController < BaseController
        DEFAULT_LIMIT = 50
        MAX_LIMIT     = 200

        def index
          restaurant = Restaurant.find(params[:restaurant_id])
          scope = Item.where(restaurant_id: restaurant.id)
                      .order(:menu_section_id, :name, :id) # :id — stable pagination on name ties
                      .includes(:item_variants, :item_modifiers, :ingredients, :tags)
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

          if params.key?(:status) && !Item::STATUSES.include?(params[:status].to_s)
            render json: { error: "invalid_status", allowed: Item::STATUSES },
                   status: :unprocessable_entity
            return
          end

          ::Admin::ItemEditor.new(item).call(edit_attrs)
          render json: serialize_item(item)
        rescue ::Admin::ItemEditor::UnknownSlug => e
          render json: { error: "unknown_#{e.kind}_slugs", slugs: e.slugs },
                 status: :unprocessable_entity
        rescue ::Admin::ItemEditor::ForeignSection
          render json: { error: "foreign_menu_section" }, status: :unprocessable_entity
        end

        private

        # Only keys the caller actually sent — an absent key must leave
        # that facet alone rather than clearing it.
        def edit_attrs
          permitted = params.permit(
            :name, :description, :status, :menu_section_id,
            ingredient_slugs: [],
            tag_slugs:        [],
            variants:  [:size, :price_cents, :currency],
            modifiers: [:name, :kind, :price_cents]
          )
          attrs = permitted.to_h.symbolize_keys
          # to_h drops keys whose value is an empty array, but "clear
          # every chip" has to survive as an explicit empty list.
          %i[ingredient_slugs tag_slugs variants modifiers].each do |key|
            attrs[key] = [] if !attrs.key?(key) && params[key].is_a?(Array) && params[key].empty?
          end
          attrs
        end

        def serialize_item(item)
          {
            id:               item.id,
            restaurant_id:    item.restaurant_id,
            menu_section_id:  item.menu_section_id,
            name:             item.name,
            description:      item.description,
            status:           item.status,
            confidence:       item.confidence,
            popularity:       item.popularity,
            ingredient_count: item.ingredient_ids.size,
            tag_count:        item.tag_ids.size,
            # Names, not just counts — the admin panel edits by slug and
            # has to show a human what's attached.
            ingredients: item.ingredients.order(:name).map { |i| { id: i.id, slug: i.slug, name: i.name } },
            tags:        item.tags.order(:name).map { |t| { id: t.id, slug: t.slug, name: t.name, family: t.family } },
            modifiers:   item.item_modifiers.order(:name).map do |m|
              { id: m.id, name: m.name, kind: m.kind, price_cents: m.price_cents }
            end,
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
