module Api
  module V1
    module Admin
      # Taxonomy CRUD (ingredients). Deliberately narrow in v1: `slug` and
      # `path` are immutable after create, destroy is refused while
      # anything points at the node, and merge + subtree rename are
      # explicitly v2. Those rules and the reasons for them live in
      # ::Taxonomy::Writer (root-scoped — a bare `Taxonomy::` here would
      # resolve under Api::V1::Admin), shared with the MCP taxonomy tools.
      # This controller is the HTTP adapter: params in, wire rows out,
      # refusals rendered by TaxonomyErrorResponse.
      class IngredientsController < BaseController
        include TaxonomyErrorResponse

        DEFAULT_LIMIT = 100
        MAX_LIMIT     = 500 # the taxonomy is small; the tree UI wants everything

        def index
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset
          scope  = Ingredient.order(:path)

          if params[:q].present?
            q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where(
              "name ILIKE :q OR EXISTS (SELECT 1 FROM unnest(aliases) AS a WHERE a ILIKE :q)",
              q: q
            )
          end

          total = scope.count
          page  = scope.limit(limit).offset(offset).to_a
          counts = ItemIngredient.where(ingredient_id: page.map(&:id)).group(:ingredient_id).count

          render json: {
            ingredients: page.map { |i| serialize_ingredient(i, counts[i.id] || 0) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def create
          ingredient = ::Taxonomy::Writer.create!(
            Ingredient,
            slug:     params.require(:slug),
            name:     params.require(:name),
            path:     params[:path].to_s,
            aliases:  Array(params[:aliases]).map(&:to_s).reject(&:blank?),
            allergen: ActiveModel::Type::Boolean.new.cast(params[:allergen]) || false
          )
          render json: serialize_ingredient(ingredient, 0), status: :created
        end

        def update
          ingredient = ::Taxonomy::Writer.update!(Ingredient.find(params[:id]), update_attrs)

          count = ItemIngredient.where(ingredient_id: ingredient.id).count
          render json: serialize_ingredient(ingredient, count)
        end

        def destroy
          ::Taxonomy::Writer.destroy!(Ingredient.find(params[:id]))
          head :no_content
        end

        private

        # slug/path go in only so the writer can refuse a change to them;
        # it never writes an immutable field.
        def update_attrs
          attrs = params.permit(:slug, :path, :name).to_h.symbolize_keys
          attrs[:aliases] = Array(params[:aliases]).map(&:to_s).reject(&:blank?) if params.key?(:aliases)
          # cast(nil) is nil and the column is NOT NULL — an explicit
          # JSON null must not become a 500.
          unless (allergen = ActiveModel::Type::Boolean.new.cast(params[:allergen])).nil?
            attrs[:allergen] = allergen
          end
          attrs
        end

        def serialize_ingredient(ingredient, items_count)
          {
            id:          ingredient.id,
            slug:        ingredient.slug,
            name:        ingredient.name,
            path:        ingredient.path.to_s,
            aliases:     ingredient.aliases,
            allergen:    ingredient.allergen,
            items_count: items_count,
            created_at:  ingredient.created_at
          }
        end
      end
    end
  end
end
