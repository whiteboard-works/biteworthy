module Api
  module V1
    module Admin
      # Taxonomy CRUD (tags). Same v1 rails as ingredients: slug, path,
      # AND family are immutable (allergen-family tags feed the filter's
      # avoid arrays; a family change would silently re-classify
      # everything referencing the tag), deletes are refused while
      # referenced, merge/subtree-rename are v2. Kept as a sibling of
      # IngredientsController rather than a shared superclass — the
      # field sets diverge enough that the abstraction costs more than
      # the ~60 duplicated lines.
      class TagsController < BaseController
        DEFAULT_LIMIT = 100
        MAX_LIMIT     = 500

        LTREE_PATH_FORMAT = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

        def index
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset
          scope  = Tag.order(:path)
          scope = scope.where(family: params[:family]) if Tag::FAMILIES.include?(params[:family].to_s)

          if params[:q].present?
            q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where("name ILIKE :q", q: q)
          end

          total = scope.count
          page  = scope.limit(limit).offset(offset).to_a
          counts = ItemTag.where(tag_id: page.map(&:id)).group(:tag_id).count

          render json: {
            tags: page.map { |t| serialize_tag(t, counts[t.id] || 0) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end

        def create
          path = params[:path].to_s
          return unless validate_path!(path)

          family = params.require(:family).to_s
          tag = Tag.create!(
            slug:        params.require(:slug),
            name:        params.require(:name),
            path:        path,
            family:      family,
            description: params[:description].presence
          )
          render json: serialize_tag(tag, 0), status: :created
        end

        def update
          tag = Tag.find(params[:id])
          immutable = %i[slug path family].select { |f| params.key?(f) && params[f].to_s != tag[f].to_s }
          if immutable.any?
            render json: { error: "immutable_field", fields: immutable }, status: :unprocessable_entity
            return
          end

          attrs = {}
          attrs[:name]        = params[:name] if params.key?(:name)
          attrs[:description] = params[:description].presence if params.key?(:description)
          tag.update!(attrs)

          render json: serialize_tag(tag, ItemTag.where(tag_id: tag.id).count)
        end

        def destroy
          tag = Tag.find(params[:id])

          references = {
            descendants: Tag.descendants_of(tag.path).where.not(id: tag.id).count,
            items:       ItemTag.where(tag_id: tag.id).count,
            presets:     DietaryProfileTag.where(tag_id: tag.id).count,
            profiles:    profiles_referencing(tag.id)
          }

          if references.values.any?(&:positive?)
            render json: { error: "in_use", references: references }, status: :conflict
            return
          end

          tag.destroy!
          head :no_content
        end

        private

        def validate_path!(path)
          unless path.match?(LTREE_PATH_FORMAT)
            render json: { error: "invalid_path" }, status: :unprocessable_entity
            return false
          end
          if path.include?(".") && !Tag.exists?(path: path.rpartition(".").first)
            render json: { error: "parent_missing", parent: path.rpartition(".").first },
                   status: :unprocessable_entity
            return false
          end
          true
        end

        def profiles_referencing(tag_id)
          UserProfile.where(
            "avoid_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "prefer_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "liked_tag_ids @> ARRAY[:id]::uuid[] OR " \
            "disliked_tag_ids @> ARRAY[:id]::uuid[]",
            id: tag_id
          ).count
        end

        def serialize_tag(tag, items_count)
          {
            id:          tag.id,
            slug:        tag.slug,
            name:        tag.name,
            path:        tag.path.to_s,
            family:      tag.family,
            description: tag.description,
            items_count: items_count,
            created_at:  tag.created_at
          }
        end
      end
    end
  end
end
