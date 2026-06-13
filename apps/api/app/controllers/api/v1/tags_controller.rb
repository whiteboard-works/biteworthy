module Api
  module V1
    # GET /api/v1/tags?families=cuisine,flavor&limit=50
    #
    # Phase 8.5 — the taste-onboarding "What do you love?" step pulls
    # cuisine + flavor chips from here. The route existed since
    # Phase 0 with no controller (hitting it 500'd) — same latent gap
    # the restaurants index had (Phase 7.2).
    #
    # `families` filters to a comma-separated subset of Tag::FAMILIES
    # (unknown names are ignored; an all-unknown filter returns []).
    # Public — onboarding runs before signup.
    class TagsController < BaseController
      skip_before_action :authenticate_user!, only: [:index]

      MAX_LIMIT     = 200
      DEFAULT_LIMIT = 100

      def index
        limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        scope = Tag.order(:family, :name).limit(limit)

        if params[:families].present?
          families = params[:families].to_s.split(",").map(&:strip) & Tag::FAMILIES
          scope = scope.where(family: families)
        end

        render json: { tags: scope.map { |t| serialize(t) } }
      end

      private

      def serialize(t)
        {
          id:     t.id,
          slug:   t.slug,
          name:   t.name,
          family: t.family
        }
      end
    end
  end
end
