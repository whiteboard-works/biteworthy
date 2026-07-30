module Api
  module V1
    module Admin
      # Taxonomy CRUD (ingredients). Deliberately narrow in v1:
      #
      #   - `slug` and `path` are IMMUTABLE after create. Ingestion
      #     payloads resolve by slug at promote time (renaming one
      #     silently drops joins — an allergen-safety P0), and an ltree
      #     path rename orphans every descendant (nothing cascades).
      #   - destroy is refused (409 + reference counts) while anything
      #     points at the node: descendants, item joins, dietary-preset
      #     rows, or user-profile avoid/taste arrays. UserProfile
      #     tolerates stale ids on read, but deleting a node in
      #     someone's avoid list would silently weaken their safety
      #     filter's intent.
      #   - merge + subtree rename are explicitly v2.
      class IngredientsController < BaseController
        DEFAULT_LIMIT = 100
        MAX_LIMIT     = 500 # the taxonomy is small; the tree UI wants everything

        LTREE_PATH_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

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
          path = params[:path].to_s
          return unless validate_path!(path)

          ingredient = Ingredient.create!(
            slug:     params.require(:slug),
            name:     params.require(:name),
            path:     path,
            aliases:  Array(params[:aliases]).map(&:to_s).reject(&:blank?),
            allergen: ActiveModel::Type::Boolean.new.cast(params[:allergen]) || false
          )
          render json: serialize_ingredient(ingredient, 0), status: :created
        end

        def update
          ingredient = Ingredient.find(params[:id])
          immutable = %i[slug path].select { |f| params.key?(f) && params[f].to_s != ingredient[f].to_s }
          if immutable.any?
            render json: { error: "immutable_field", fields: immutable }, status: :unprocessable_entity
            return
          end

          attrs = {}
          attrs[:name]    = params[:name] if params.key?(:name)
          attrs[:aliases] = Array(params[:aliases]).map(&:to_s).reject(&:blank?) if params.key?(:aliases)
          # cast(nil) is nil and the column is NOT NULL — an explicit
          # JSON null must not become a 500.
          unless (allergen = ActiveModel::Type::Boolean.new.cast(params[:allergen])).nil?
            attrs[:allergen] = allergen
          end
          ingredient.update!(attrs)

          count = ItemIngredient.where(ingredient_id: ingredient.id).count
          render json: serialize_ingredient(ingredient, count)
        end

        def destroy
          ingredient = Ingredient.find(params[:id])

          # Transaction + row lock narrows the check-then-destroy race
          # (dependent: :destroy would silently cascade a join added in
          # between). A concurrent INSERT can still slip past — admin-only
          # endpoint, accepted.
          ingredient.transaction do
            ingredient.lock!

            references = {
              # `<@` includes the node itself — exclude it.
              descendants: Ingredient.descendants_of(ingredient.path).where.not(id: ingredient.id).count,
              items:       ItemIngredient.where(ingredient_id: ingredient.id).count,
              presets:     DietaryProfileIngredient.where(ingredient_id: ingredient.id).count,
              modifiers:   ItemModifier.where("ingredient_ids @> ARRAY[:id]::uuid[]", id: ingredient.id).count,
              profiles:    profiles_referencing(ingredient.id)
            }

            if references.values.any?(&:positive?)
              render json: { error: "in_use", references: references }, status: :conflict
            else
              ingredient.destroy!
              head :no_content
            end
          end
        end

        private

        def validate_path!(path)
          unless path.match?(LTREE_PATH_FORMAT)
            render json: { error: "invalid_path" }, status: :unprocessable_entity
            return false
          end
          if path.include?(".") && !Ingredient.exists?(path: path.rpartition(".").first)
            render json: { error: "parent_missing", parent: path.rpartition(".").first },
                   status: :unprocessable_entity
            return false
          end
          true
        end

        # The avoid array is GIN-indexed; the taste arrays aren't —
        # taxonomy deletes are rare enough that a seq scan is fine.
        def profiles_referencing(ingredient_id)
          UserProfile.where(
            "avoid_ingredient_ids @> ARRAY[:id]::uuid[] OR " \
            "liked_ingredient_ids @> ARRAY[:id]::uuid[] OR " \
            "disliked_ingredient_ids @> ARRAY[:id]::uuid[]",
            id: ingredient_id
          ).count
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
