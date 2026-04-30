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

      rescue_from ProfileToken::InvalidTokenError do |e|
        render json: { error: "Invalid profile_token: #{e.message}" }, status: :unprocessable_entity
      end

      def index
        restaurant = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id])
        items      = restaurant.items.published
                               .includes(menu_section: :menu)
                               .order(popularity: :desc, name: :asc)
                               .to_a

        filter        = build_filter
        labels        = build_label_lookup(items, filter)
        override_ids  = current_user_override_item_ids(items)
        review_counts = review_counts_for(items)
        rendered      = items.map { |item| serialize_item(item, filter, labels, override_ids, review_counts) }

        render json: {
          restaurant_id: restaurant.id,
          filter: filter_summary(filter),
          items:  rendered
        }
      end

      def show
        item = Restaurant.published.find_by_id_or_slug!(params[:restaurant_id]).items.published.find(params[:id])
        filter = build_filter
        render json: serialize_item(item, filter, build_label_lookup([item], filter), current_user_override_item_ids([item]), review_counts_for([item]))
      end

      private

      Filter = Struct.new(:avoid_ingredient_ids, :avoid_tag_ids, :strictness, :source, :preset_slug, keyword_init: true)

      def build_filter
        if params[:profile_token].present?
          decoded = ProfileToken.decode(params[:profile_token])
          # ?strictness=... overrides what the token encoded so a
          # strict-mode toggle still works on a shared link.
          Filter.new(
            avoid_ingredient_ids: decoded.avoid_ingredient_ids,
            avoid_tag_ids:        decoded.avoid_tag_ids,
            strictness:           strictness_param || decoded.strictness,
            source:               "profile_token",
            preset_slug:          nil
          )
        elsif params[:profile].present?
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
      # An empty reasons array means the item passes the filter. Each
      # reason is enriched with display strings (`*_name`, `*_family`)
      # so the mobile/web HiddenReasonChip is a pure render — no
      # second roundtrip to look up names.
      def hide_reasons(item, filter, labels)
        reasons = []

        (item.ingredient_ids & filter.avoid_ingredient_ids).each do |ing_id|
          ing = labels[:ingredients][ing_id]
          reasons << {
            kind:              "avoid_ingredient",
            ingredient_id:     ing_id,
            ingredient_name:   ing&.dig(:name),
            ingredient_family: ing&.dig(:family)
          }
        end
        (item.tag_ids & filter.avoid_tag_ids).each do |tag_id|
          tag = labels[:tags][tag_id]
          reasons << {
            kind:       "avoid_tag",
            tag_id:     tag_id,
            tag_name:   tag&.dig(:name),
            tag_family: tag&.dig(:family)
          }
        end
        if filter.strictness == "strict" && item.confidence != "confirmed"
          reasons << { kind: "unconfirmed_strict", confidence: item.confidence }
        end

        reasons
      end

      # Bulk-load names + family strings for every ingredient/tag id
      # the filter could possibly cite. Keyed by id so `hide_reasons`
      # is a hash lookup. Family for ingredients = first ltree segment
      # (e.g. `dairy.cheddar` -> `dairy`); for tags it's the model
      # column.
      def build_label_lookup(items, filter)
        cited_ingredient_ids = items.flat_map(&:ingredient_ids).uniq & filter.avoid_ingredient_ids
        cited_tag_ids        = items.flat_map(&:tag_ids).uniq        & filter.avoid_tag_ids

        ingredient_labels = Ingredient.where(id: cited_ingredient_ids)
                                      .pluck(:id, :name, :path)
                                      .to_h { |id, name, path| [id, { name: name, family: path.to_s.split(".").first }] }

        tag_labels = Tag.where(id: cited_tag_ids)
                        .pluck(:id, :name, :family)
                        .to_h { |id, name, family| [id, { name: name, family: family }] }

        { ingredients: ingredient_labels, tags: tag_labels }
      end

      # Try to keep this stable — mobile + web bind to these keys via
      # generated TS types; Phase 1.6's openapi.json should match.
      def serialize_item(item, filter, labels, override_ids = Set.new, review_counts = {})
        reasons = hide_reasons(item, filter, labels)
        section = item.menu_section
        {
          id:                  item.id,
          restaurant_id:       item.restaurant_id,
          name:                item.name,
          description:         item.description,
          confidence:          item.confidence,
          popularity:          item.popularity,
          ingredient_ids:      item.ingredient_ids,
          tag_ids:             item.tag_ids,
          menu_section_id:     section&.id,
          menu_section_name:   section&.name,
          status:              reasons.empty? ? "visible" : "hidden",
          reasons:             reasons,
          overridden_by_user:  override_ids.include?(item.id),
          reviews_count:       review_counts.fetch(item.id, 0)
        }
      end

      # Phase 4.4 — bulk-load review counts for the items in the
      # response. One grouped query, joined client-side so the
      # restaurant page can render an "X reviews" badge per item
      # without N+1.
      def review_counts_for(items)
        ids = items.map(&:id)
        return {} if ids.empty?
        Review.where(item_id: ids).group(:item_id).count
      end

      # Phase 4.2 — bulk-load the authenticated user's "never hide"
      # overrides for the items in this response. Returns an empty
      # Set when anonymous so the boolean stays accurate (anonymous
      # callers always see `overridden_by_user: false`).
      def current_user_override_item_ids(items)
        return Set.new unless current_user
        ids = items.map(&:id)
        return Set.new if ids.empty?
        Set.new(
          UserItemOverride.where(user_id: current_user.id, item_id: ids, never_hide: true).pluck(:item_id)
        )
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
