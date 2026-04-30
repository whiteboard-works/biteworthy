module Api
  module V1
    # GET /api/v1/dietary_profiles
    #
    # Phase 3.2 — the mobile + web onboarding flows fetch this to
    # render the preset chip picker. Returns each preset with its
    # avoid_ingredient_ids + avoid_tag_ids so the client can apply
    # the picks to the draft profile additively.
    #
    # Public (unauthenticated) — anonymous users can browse presets
    # before signing up.
    class DietaryProfilesController < BaseController
      skip_before_action :authenticate_user!, only: [:index]

      def index
        presets = DietaryProfile
          .includes(:dietary_profile_ingredients, :dietary_profile_tags)
          .order(:name)

        render json: { dietary_profiles: presets.map { |p| serialize(p) } }
      end

      private

      def serialize(p)
        {
          id:                   p.id,
          slug:                 p.slug,
          name:                 p.name,
          description:          p.description,
          avoid_ingredient_ids: p.dietary_profile_ingredients.where(rule: "avoid").pluck(:ingredient_id),
          avoid_tag_ids:        p.dietary_profile_tags.where(rule: "avoid").pluck(:tag_id)
        }
      end
    end
  end
end
