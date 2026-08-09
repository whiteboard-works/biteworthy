module Api
  module V1
    module Admin
      # Taxonomy CRUD (tags). Same v1 rails as ingredients, plus an
      # immutable `family` — allergen-family tags feed the filter's avoid
      # arrays, so a family change would silently re-classify everything
      # referencing the tag. The rails live in ::Taxonomy::Writer, shared
      # with IngredientsController and the MCP taxonomy tools; this file
      # is still a sibling rather than a subclass because what is left —
      # the field set and the wire row — is where the two genuinely
      # differ. (The comment this replaces argued the duplication was
      # cheaper than the abstraction. It was written when there were two
      # copies of the rules; a third arrived with the tool layer and they
      # stopped agreeing.)
      class TagsController < BaseController
        include TaxonomyErrorResponse

        DEFAULT_LIMIT = 100
        MAX_LIMIT     = 500

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
          tag = ::Taxonomy::Writer.create!(
            Tag,
            slug:        params.require(:slug),
            name:        params.require(:name),
            path:        params[:path].to_s,
            family:      params.require(:family).to_s,
            description: params[:description].presence
          )
          render json: serialize_tag(tag, 0), status: :created
        end

        def update
          tag = ::Taxonomy::Writer.update!(Tag.find(params[:id]), update_attrs)

          render json: serialize_tag(tag, ItemTag.where(tag_id: tag.id).count)
        end

        def destroy
          ::Taxonomy::Writer.destroy!(Tag.find(params[:id]))
          head :no_content
        end

        private

        # slug/path/family go in only so the writer can refuse a change to
        # them; it never writes an immutable field.
        def update_attrs
          attrs = params.permit(:slug, :path, :family, :name).to_h.symbolize_keys
          attrs[:description] = params[:description].presence if params.key?(:description)
          attrs
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
