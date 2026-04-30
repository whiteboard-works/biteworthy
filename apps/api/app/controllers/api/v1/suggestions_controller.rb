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
      skip_before_action :authenticate_user!, only: [:create]
      before_action :load_item,       only: [:create]
      before_action :load_restaurant, only: [:index]
      before_action :load_suggestion, only: [:update]

      def create
        kind    = params[:kind].to_s
        payload = params[:payload].is_a?(ActionController::Parameters) ? params[:payload].to_unsafe_h : {}

        unless SuggestionResolver::ITEM_KINDS.include?(kind)
          return render json: {
            error: "Unsupported kind",
            allowed: SuggestionResolver::ITEM_KINDS
          }, status: :unprocessable_entity
        end

        suggestion = Suggestion.create!(
          user:    current_user,
          subject: @item,
          kind:    kind,
          status:  "pending",
          payload: payload
        )
        render json: serialize(suggestion), status: :created
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

      def load_item
        @item = Item.published.find(params[:item_id])
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

      def serialize(suggestion)
        item = suggestion.subject
        {
          id:      suggestion.id,
          kind:    suggestion.kind,
          status:  suggestion.status,
          payload: suggestion.payload,
          created_at: suggestion.created_at,
          resolved_at: suggestion.resolved_at,
          item: item.is_a?(Item) ? { id: item.id, name: item.name, restaurant_id: item.restaurant_id } : nil,
          submitter: suggestion.user.then { |u|
            u ? { id: u.id, handle: u.handle, display_name: u.display_name } : nil
          }
        }
      end
    end
  end
end
