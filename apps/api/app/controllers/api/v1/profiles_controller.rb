module Api
  module V1
    # Minimal stub. Real GET/PATCH semantics — including avoid/prefer
    # array round-trip and dietary-profile preset application — land
    # in Phase 1.3 (`docs/plans/phase-1.md#13`). For now this just
    # exists so authenticated callers can check that their token is
    # still valid (and unauthenticated ones get a clean 401).
    class ProfilesController < BaseController
      def show
        render json: profile_payload(current_user.profile)
      end

      private

      def profile_payload(profile)
        {
          avoid_ingredient_ids: profile.avoid_ingredient_ids,
          avoid_tag_ids:        profile.avoid_tag_ids,
          prefer_tag_ids:       profile.prefer_tag_ids,
          strictness:           profile.strictness
        }
      end
    end
  end
end
