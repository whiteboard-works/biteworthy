module Api
  module V1
    # GET /api/v1/restaurants/:restaurant_id/items
    #
    # Returns every published item at the given restaurant, with each
    # item carrying a per-item filter status + reasons[] array. The UI
    # uses `status: "hidden"` to grey-out an item and renders the
    # reasons inline (e.g., "Hidden — contains dairy (Cheddar)").
    #
    # Filter source:
    #   ?profile=<dietary_profile_slug>  → use that preset's avoid lists
    #   ?strictness=relaxed|balanced|strict → strict-mode toggle
    #   no params + signed-in user → use current_user.profile
    #   no params + anonymous → no filtering (everything visible)
    #
    # The endpoint is intentionally unauthenticated — Phase 3 mobile
    # users browse menus before they create an account.
    class ItemsController < BaseController
      skip_before_action :authenticate_user!, only: [:index, :show]

      def index
        restaurant = Restaurant.published.find(params[:restaurant_id])
        items      = restaurant.items.published.order(popularity: :desc, name: :asc).to_a

        filter = build_filter
        rendered = items.map { |item| serialize_item(item, filter) }

        render json: {
          restaurant_id: restaurant.id,
          filter: filter_summary(filter),
          items:  rendered
        }
      end

      def show
        item = Restaurant.published.find(params[:restaurant_id]).items.published.find(params[:id])
        render json: serialize_item(item, build_filter)
      end

      private

      Filter = Struct.new(:avoid_ingredient_ids, :avoid_tag_ids, :strictness, :source, :preset_slug, keyword_init: true)

      def build_filter
        if params[:profile].present?
          preset = DietaryProfile.includes(:dietary_profile_ingredients, :dietary_profile_tags)
                                 .find_by!(slug: params[:profile])
          Filter.new(
            avoid_ingredient_ids: preset.dietary_profile_ingredients.where(rule: "avoid").pluck(:ingredient_id),
            avoid_tag_ids:        preset.dietary_profile_tags.where(rule: "avoid").pluck(:tag_id),
            strictness:           strictness_param || "balanced",
            source:               "preset",
            preset_slug:          preset.slug
          )
        elsif current_user&.profile
          p = current_user.profile
          Filter.new(
            avoid_ingredient_ids: p.avoid_ingredient_ids,
            avoid_tag_ids:        p.avoid_tag_ids,
            strictness:           strictness_param || p.strictness,
            source:               "user_profile",
            preset_slug:          nil
          )
        else
          Filter.new(
            avoid_ingredient_ids: [],
            avoid_tag_ids:        [],
            strictness:           strictness_param || "balanced",
            source:               "none",
            preset_slug:          nil
          )
        end
      end

      def strictness_param
        return nil if params[:strictness].blank?
        UserProfile::STRICTNESS.include?(params[:strictness]) ? params[:strictness] : nil
      end

      # Compute reasons WHY an item would be hidden under this filter.
      # An empty reasons array means the item passes the filter.
      def hide_reasons(item, filter)
        reasons = []

        (item.ingredient_ids & filter.avoid_ingredient_ids).each do |ing_id|
          reasons << { kind: "avoid_ingredient", ingredient_id: ing_id }
        end
        (item.tag_ids & filter.avoid_tag_ids).each do |tag_id|
          reasons << { kind: "avoid_tag", tag_id: tag_id }
        end
        if filter.strictness == "strict" && item.confidence != "confirmed"
          reasons << { kind: "unconfirmed_strict", confidence: item.confidence }
        end

        reasons
      end

      # Try to keep this stable — mobile + web bind to these keys via
      # generated TS types; Phase 1.6's openapi.json should match.
      def serialize_item(item, filter)
        reasons = hide_reasons(item, filter)
        {
          id:             item.id,
          restaurant_id:  item.restaurant_id,
          name:           item.name,
          description:    item.description,
          confidence:     item.confidence,
          popularity:     item.popularity,
          ingredient_ids: item.ingredient_ids,
          tag_ids:        item.tag_ids,
          status:         reasons.empty? ? "visible" : "hidden",
          reasons:        reasons
        }
      end

      def filter_summary(filter)
        {
          source:               filter.source,
          preset_slug:          filter.preset_slug,
          strictness:           filter.strictness,
          avoid_ingredient_ids: filter.avoid_ingredient_ids,
          avoid_tag_ids:        filter.avoid_tag_ids
        }
      end
    end
  end
end
