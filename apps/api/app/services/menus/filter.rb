# frozen_string_literal: true

module Menus
  # Who the caller is avoiding, and how strict they want us to be.
  #
  # This used to live inside Api::V1::ItemsController. It moved here when
  # the MCP tool layer landed: `get_menu` and `GET /restaurants/:id/items`
  # must answer "why is this hidden?" identically, and two copies of
  # `reasons_for` would drift. `reasons_for` below is now the ONLY
  # implementation of the rule — web and mobile render the `status` /
  # `reasons` they receive and never recompute them.
  #
  # Precedence when building: an explicit share token beats a named preset,
  # which beats the signed-in user's saved profile, which beats no filter
  # at all. `strictness` is separately overridable at every level so the
  # strict-mode toggle still works on a shared link.
  Filter = Struct.new(
    :avoid_ingredient_ids,
    :avoid_tag_ids,
    :strictness,
    :source,
    :preset_slug,
    keyword_init: true
  )

  class Filter
    DEFAULT_STRICTNESS = "balanced"

    class << self
      # Raises ProfileToken::InvalidTokenError for a malformed token and
      # ActiveRecord::RecordNotFound for an unknown preset slug — callers
      # decide how to surface each.
      def build(user: nil, profile_token: nil, preset_slug: nil, strictness: nil)
        override = normalize_strictness(strictness)

        filter =
          if profile_token.present?
            from_token(profile_token, strictness: override)
          elsif preset_slug.present?
            from_preset(preset_slug, strictness: override)
          elsif user&.profile
            from_user_profile(user.profile, strictness: override)
          else
            none(strictness: override)
          end

        resolve_subtrees(filter)
      end

      # Avoiding a node means avoiding everything under it — "I avoid
      # dairy" has to hide the dish tagged `dairy-cheddar`. Applied once
      # here rather than in each `from_*` so no source can be added that
      # quietly skips it. Public because `Cities::RestaurantRanking`
      # counts the same dishes in SQL and has to expand the same way, or
      # its `visible_count` outruns the menu it links to.
      def resolve_subtrees(filter)
        filter.avoid_ingredient_ids = Subtree.ingredient_ids(filter.avoid_ingredient_ids)
        filter.avoid_tag_ids        = Subtree.tag_ids(filter.avoid_tag_ids)
        filter
      end

      def from_token(token, strictness: nil)
        decoded = ProfileToken.decode(token)
        verify_token_ids!(decoded)
        new(
          avoid_ingredient_ids: decoded.avoid_ingredient_ids,
          avoid_tag_ids:        decoded.avoid_tag_ids,
          strictness:           strictness || decoded.strictness,
          source:               "profile_token",
          preset_slug:          nil
        )
      end

      # A shared link is a claim: *this menu is filtered to my profile*.
      # `ProfileToken.decode` can only check the shape of what it was
      # handed, and a well-formed UUID naming nothing expands to no
      # subtree and matches no dish — so the claim would be made over a
      # menu that is not filtered at all. Shape alone therefore does not
      # close the hole it looks like it closes; membership does, and it
      # is checked here because this is the layer that already has the
      # database. Caught by Codex on #605.
      #
      # **Refusing the whole token is the point.** These ids can go stale
      # when an admin removes a taxonomy node, which is exactly when the
      # link stops meaning what it says — and "this link is no longer
      # valid" (`ItemsController` turns it into a 422) is a far better
      # answer to someone with an allergy than a menu quietly missing one
      # of its reasons. That is the opposite of the call in
      # `UserProfile#avoid_ids_are_real`, deliberately: there, refusing a
      # stale id would lock a person out of editing their own filter, so
      # only newly-added ids are checked. The person can fix a profile.
      # Nobody can fix a link.
      def verify_token_ids!(decoded)
        missing = decoded.avoid_ingredient_ids -
                  Ingredient.where(id: decoded.avoid_ingredient_ids).pluck(:id)
        missing += decoded.avoid_tag_ids -
                   Tag.where(id: decoded.avoid_tag_ids).pluck(:id)
        return if missing.empty?

        raise ProfileToken::InvalidTokenError,
              "refers to #{missing.size} ingredient or tag that no longer exists"
      end

      def from_preset(slug, strictness: nil)
        preset = DietaryProfile.includes(:dietary_profile_ingredients, :dietary_profile_tags)
                               .find_by!(slug: slug)
        new(
          avoid_ingredient_ids: preset.avoid_ingredient_ids,
          avoid_tag_ids:        preset.avoid_tag_ids,
          strictness:           strictness || DEFAULT_STRICTNESS,
          source:               "preset",
          preset_slug:          preset.slug
        )
      end

      def from_user_profile(profile, strictness: nil)
        new(
          avoid_ingredient_ids: profile.avoid_ingredient_ids,
          avoid_tag_ids:        profile.avoid_tag_ids,
          strictness:           strictness || profile.strictness,
          source:               "user_profile",
          preset_slug:          nil
        )
      end

      def none(strictness: nil)
        new(
          avoid_ingredient_ids: [],
          avoid_tag_ids:        [],
          strictness:           strictness || DEFAULT_STRICTNESS,
          source:               "none",
          preset_slug:          nil
        )
      end

      # Unknown values fall through to nil so the caller's own default
      # wins — an unrecognized ?strictness= must not silently relax a
      # strict profile.
      def normalize_strictness(value)
        return nil if value.blank?
        UserProfile::STRICTNESS.include?(value) ? value : nil
      end
    end

    # Compute reasons WHY this item would be hidden under this filter.
    # An empty array means the item passes. Each reason carries display
    # strings (`*_name`, `*_family`) so the client's HiddenReasonChip is
    # a pure render with no second roundtrip.
    def reasons_for(item, labels)
      reasons = []

      (item.denormalized_ingredient_ids & avoid_ingredient_ids).each do |ing_id|
        ing = labels[:ingredients][ing_id]
        reasons << {
          kind:              "avoid_ingredient",
          ingredient_id:     ing_id,
          ingredient_name:   ing&.dig(:name),
          ingredient_family: ing&.dig(:family)
        }
      end
      (item.denormalized_tag_ids & avoid_tag_ids).each do |tag_id|
        tag = labels[:tags][tag_id]
        reasons << {
          kind:       "avoid_tag",
          tag_id:     tag_id,
          tag_name:   tag&.dig(:name),
          tag_family: tag&.dig(:family)
        }
      end
      if strictness == "strict" && item.confidence != "confirmed"
        reasons << { kind: "unconfirmed_strict", confidence: item.confidence }
      end

      reasons
    end

    # Taste signals come ONLY from the signed-in user's saved profile —
    # presets and share tokens carry no taste. Ids that also sit in an
    # avoid list are subtracted here: filter wins, and an avoided id never
    # scores (Phase 8.1 contract).
    def taste_signals_for(user)
      return nil unless source == "user_profile"
      return nil unless user&.profile

      p = user.profile
      TasteScoring::Signals.new(
        liked_ingredient_ids:    p.liked_ingredient_ids    - avoid_ingredient_ids,
        liked_tag_ids:           p.liked_tag_ids           - avoid_tag_ids,
        disliked_ingredient_ids: p.disliked_ingredient_ids - avoid_ingredient_ids,
        disliked_tag_ids:        p.disliked_tag_ids        - avoid_tag_ids
      )
    end

    def summary
      {
        source:               source,
        preset_slug:          preset_slug,
        strictness:           strictness,
        avoid_ingredient_ids: avoid_ingredient_ids,
        avoid_tag_ids:        avoid_tag_ids
      }
    end
  end
end
