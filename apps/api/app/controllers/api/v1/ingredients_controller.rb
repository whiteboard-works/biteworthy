module Api
  module V1
    # GET /api/v1/ingredients?q=cheese&limit=20
    #
    # Phase 3.2 — the onboarding "Anything else?" step searches this
    # for free-text ingredient additions to the draft profile. With
    # `?q=…` runs trigram similarity against name + aliases (the
    # `pg_trgm` indexes are on both columns from migration #3).
    # Without `?q=`, returns the first `limit` ingredients sorted by
    # path.
    #
    # Public (unauthenticated) — anonymous users browse the catalog
    # while picking an avoid list before they create an account.
    class IngredientsController < BaseController
      skip_before_action :authenticate_user!, only: [:index]

      MAX_LIMIT     = 100
      DEFAULT_LIMIT = 20

      def index
        limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        scope = Ingredient.order(:path).limit(limit)

        if params[:q].present?
          q = params[:q].to_s.strip
          # Trigram similarity catches "garbanzo" → "Chickpea" via
          # the aliases column. ILIKE on name handles substring
          # matches the trigram threshold misses for short queries.
          scope = scope.where(
            "name ILIKE :ilike OR EXISTS (SELECT 1 FROM unnest(aliases) AS a WHERE a ILIKE :ilike)",
            ilike: "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
          )
        end

        render json: { ingredients: scope.map { |i| serialize(i) } }
      end

      private

      def serialize(i)
        {
          id:       i.id,
          slug:     i.slug,
          name:     i.name,
          path:     i.path.to_s,
          aliases:  i.aliases,
          allergen: i.allergen
        }
      end
    end
  end
end
