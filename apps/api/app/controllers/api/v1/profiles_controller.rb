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

        # Legal remediation E1 — `acknowledge_disclaimer: true` records
        # that the user saw and accepted the in-app allergen disclaimer
        # (onboarding sends it on the final save). The time is stamped
        # server-side, not taken from the client, and only the first
        # acknowledgment is kept.
        if ActiveModel::Type::Boolean.new.cast(params[:acknowledge_disclaimer]) &&
           profile.disclaimer_acknowledged_at.nil?
          profile.disclaimer_acknowledged_at = Time.current
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
          prefer_tag_ids:       [],
          # Phase 8.1 — taste signals (soft: rank, never hide). Same
          # wholesale-replacement semantics as the avoid arrays.
          liked_ingredient_ids:    [],
          liked_tag_ids:           [],
          disliked_ingredient_ids: [],
          disliked_tag_ids:        []
        )
      end

      def apply_preset!(profile, preset)
        profile.avoid_ingredient_ids = (profile.avoid_ingredient_ids + preset.avoid_ingredient_ids).uniq
        profile.avoid_tag_ids        = (profile.avoid_tag_ids        + preset.avoid_tag_ids).uniq
        profile.primary_dietary_profile_id = preset.id
      end

      # The raw id arrays stay (mobile onboarding + filter-engine read
      # them); the `*_ingredients` / `*_tags` arrays add the resolved
      # {id, slug, name} rows the web account page renders without a
      # second round-trip. Unknown/stale ids resolve to nothing and drop
      # out — the same way scoring silently ignores them.
      def profile_payload(profile)
        {
          avoid_ingredient_ids: profile.avoid_ingredient_ids,
          avoid_tag_ids:        profile.avoid_tag_ids,
          prefer_tag_ids:       profile.prefer_tag_ids,
          liked_ingredient_ids:    profile.liked_ingredient_ids,
          liked_tag_ids:           profile.liked_tag_ids,
          disliked_ingredient_ids: profile.disliked_ingredient_ids,
          disliked_tag_ids:        profile.disliked_tag_ids,
          avoid_ingredients:    resolve_ingredients(profile.avoid_ingredient_ids),
          avoid_tags:           resolve_tags(profile.avoid_tag_ids),
          prefer_tags:          resolve_tags(profile.prefer_tag_ids),
          liked_ingredients:    resolve_ingredients(profile.liked_ingredient_ids),
          liked_tags:           resolve_tags(profile.liked_tag_ids),
          disliked_ingredients: resolve_ingredients(profile.disliked_ingredient_ids),
          disliked_tags:        resolve_tags(profile.disliked_tag_ids),
          strictness:           profile.strictness,
          primary_dietary_profile: dietary_profile_summary(profile.primary_dietary_profile),
          disclaimer_acknowledged_at: profile.disclaimer_acknowledged_at&.iso8601
        }
      end

      # Resolve an id array to ordered {id, slug, name} rows, dropping
      # any id that no longer maps to a live row. One query, order
      # preserved from the stored array.
      def resolve_ingredients(ids)
        by_id = Ingredient.where(id: ids).index_by { |i| i.id.to_s }
        ids.filter_map do |id|
          ing = by_id[id.to_s]
          { id: ing.id, slug: ing.slug, name: ing.name } if ing
        end
      end

      def resolve_tags(ids)
        by_id = Tag.where(id: ids).index_by { |t| t.id.to_s }
        ids.filter_map do |id|
          tag = by_id[id.to_s]
          { id: tag.id, slug: tag.slug, name: tag.name, family: tag.family } if tag
        end
      end

      def dietary_profile_summary(preset)
        return nil if preset.nil?
        { id: preset.id, slug: preset.slug, name: preset.name }
      end
    end
  end
end
