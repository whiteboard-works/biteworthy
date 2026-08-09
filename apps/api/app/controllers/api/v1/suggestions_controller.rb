module Api
  module V1
    # Phase 4.10 — community-edit suggestions on items + the
    # claimed-restaurant owner's review queue.
    #
    #   POST   /api/v1/items/:item_id/suggestions
    #     Anyone (signed in or not). Anonymous suggestions land with
    #     user_id: nil and skip the polite "thanks for contributing"
    #     attribution but still queue for the owner.
    #
    #   GET    /api/v1/restaurants/:restaurant_id/suggestions
    #     Authenticated. Returns pending suggestions on items
    #     belonging to this restaurant. Gated to the restaurant's
    #     `claimed_by_user_id` (or admin).
    #
    #   PATCH  /api/v1/suggestions/:id
    #     Authenticated owner of the related restaurant (or admin).
    #     `{ decision: 'accepted' | 'rejected' }` — accept routes
    #     through SuggestionResolver to materialize the change.
    class SuggestionsController < BaseController
      include SuggestionPayload

      skip_before_action :authenticate_user!, only: [:create]
      before_action :load_item,       only: [:create]
      before_action :load_restaurant, only: [:index]
      before_action :load_suggestion, only: [:update]

      def create
        kind = params[:kind].to_s

        unless SuggestionResolver::ITEM_KINDS.include?(kind)
          return render json: {
            error: "Unsupported kind",
            allowed: SuggestionResolver::ITEM_KINDS
          }, status: :unprocessable_entity
        end

        # Built rather than accepted. This used to be
        # `params[:payload].to_unsafe_h` — whatever arrived went into the
        # jsonb column, so a typo'd slug queued fine and only failed days
        # later in front of the owner, who cannot fix it. The tool door
        # has validated at submit time since M3a; this is the same rule,
        # not a second one.
        suggestion = Suggestion.create!(
          user:    current_user,
          subject: @item,
          kind:    kind,
          status:  "pending",
          payload: ::Suggestions::PayloadBuilder.call(kind: kind, **submitted_fields)
        )
        render json: serialize(suggestion), status: :created
      rescue ::Suggestions::PayloadBuilder::InvalidPayload => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def index
        gate_owner!(@restaurant) or return

        suggestions = Suggestion.includes(:user, :subject)
                                .where(subject_type: "Item", subject_id: @restaurant.items.select(:id))
                                .where(status: "pending")
                                .order(created_at: :asc)

        render json: { suggestions: suggestions.map { |s| serialize(s) } }
      end

      def update
        item = @suggestion.subject
        return render json: { error: "Subject is not an Item" }, status: :unprocessable_entity unless item.is_a?(Item)
        gate_owner!(item.restaurant) or return

        decision = params[:decision].to_s
        case decision
        when "accepted"
          SuggestionResolver.accept!(@suggestion, by_user: current_user)
        when "rejected"
          SuggestionResolver.reject!(@suggestion, by_user: current_user)
        else
          return render json: { error: "decision must be 'accepted' or 'rejected'" }, status: :unprocessable_entity
        end
        render json: serialize(@suggestion)
      rescue SuggestionResolver::InvalidPayloadError => e
        render json: { error: e.message, kind: "InvalidPayloadError" }, status: :unprocessable_entity
      rescue SuggestionResolver::UnsupportedKindError => e
        render json: { error: e.message, kind: "UnsupportedKindError" }, status: :unprocessable_entity
      end

      private

      # The wire shape is `payload: { ingredient_slug | tag_slug | name }`
      # and stays that way — apps/web and apps/mobile both post it. Which
      # key carries the slug depends on the kind, so the mapping lives
      # with the rule rather than here.
      def submitted_fields
        payload = params[:payload].is_a?(ActionController::Parameters) ? params[:payload].to_unsafe_h : {}
        {
          slug: ::Suggestions::PayloadBuilder.slug_from(payload),
          name: payload["name"]
        }
      end

      def load_item
        @item = Item.published.joins(:restaurant).merge(Restaurant.published).find(params[:item_id])
      end

      def load_restaurant
        @restaurant = Restaurant.find_by_id_or_slug!(params[:restaurant_id])
      end

      def load_suggestion
        @suggestion = Suggestion.find(params[:id])
      end

      # Returns true if the caller may act as owner; renders 403 +
      # returns nil otherwise. Caller pattern: `gate_owner!(...) or return`.
      def gate_owner!(restaurant)
        return true if current_user&.is_admin?
        return true if restaurant.claimed_by_user_id.present? && restaurant.claimed_by_user_id == current_user&.id
        render json: { error: "Only the claimed-restaurant owner can do that" }, status: :forbidden
        nil
      end

      # Serialization moved to the SuggestionPayload concern (shared
      # with the admin queue).
      def serialize(suggestion)
        suggestion_payload(suggestion)
      end
    end
  end
end
