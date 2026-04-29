module Api
  module V1
    # GET   /api/v1/profile  → returns the caller's dietary settings.
    # PATCH /api/v1/profile  → replaces the avoid/prefer arrays wholesale
    #                          and/or applies a dietary_profile preset
    #                          (additive — never destructive).
    #
    # Replacement semantics: PATCH treats avoid_ingredient_ids,
    # avoid_tag_ids, prefer_tag_ids, and strictness as a wholesale
    # overwrite of whatever's stored. The mobile + web clients build
    # the final array client-side and POST the canonical state — they
    # are not sending diffs.
    #
    # Preset application: if the body carries `dietary_profile_slug`,
    # that preset's avoid_ingredients + avoid_tags are unioned onto
    # whatever the client just sent. Presets only ADD; they never
    # remove rules the user already chose. The chosen preset is also
    # recorded as `primary_dietary_profile_id` so onboarding flows
    # can show "you picked Vegan" later.
    class ProfilesController < BaseController
      def show
        render json: profile_payload(current_user.profile)
      end

      def update
        profile = current_user.profile
        attrs   = profile_params

        # Wholesale replacement happens first; the preset (if any)
        # then unions on top so the user's POSTed list is never a
        # subset of what gets saved.
        profile.assign_attributes(attrs.except(:dietary_profile_slug))

        if (slug = attrs[:dietary_profile_slug]).present?
          preset = DietaryProfile.includes(:dietary_profile_ingredients,
                                           :dietary_profile_tags)
                                 .find_by!(slug: slug)
          apply_preset!(profile, preset)
        end

        if profile.save
          render json: profile_payload(profile)
        else
          render json: { errors: profile.errors.as_json },
                 status: :unprocessable_entity
        end
      end

      private

      def profile_params
        params.permit(
          :strictness,
          :dietary_profile_slug,
          avoid_ingredient_ids: [],
          avoid_tag_ids:        [],
          prefer_tag_ids:       []
        )
      end

      def apply_preset!(profile, preset)
        avoid_ingredients = preset.dietary_profile_ingredients
                                  .where(rule: "avoid").pluck(:ingredient_id)
        avoid_tags        = preset.dietary_profile_tags
                                  .where(rule: "avoid").pluck(:tag_id)

        profile.avoid_ingredient_ids = (profile.avoid_ingredient_ids + avoid_ingredients).uniq
        profile.avoid_tag_ids        = (profile.avoid_tag_ids        + avoid_tags).uniq
        profile.primary_dietary_profile_id = preset.id
      end

      def profile_payload(profile)
        {
          avoid_ingredient_ids: profile.avoid_ingredient_ids,
          avoid_tag_ids:        profile.avoid_tag_ids,
          prefer_tag_ids:       profile.prefer_tag_ids,
          strictness:           profile.strictness,
          primary_dietary_profile: dietary_profile_summary(profile.primary_dietary_profile)
        }
      end

      def dietary_profile_summary(preset)
        return nil if preset.nil?
        { id: preset.id, slug: preset.slug, name: preset.name }
      end
    end
  end
end
