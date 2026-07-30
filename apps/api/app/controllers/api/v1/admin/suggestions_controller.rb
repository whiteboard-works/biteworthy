module Api
  module V1
    module Admin
      # GET /api/v1/admin/suggestions — the cross-restaurant suggestion
      # queue. The owner queue (Phase 4.10) only shows a claimed
      # restaurant's suggestions to its owner; most restaurants are
      # unclaimed, so their queue was previously reachable only through
      # Avo. Accept/reject reuses the existing PATCH
      # /api/v1/suggestions/:id (admins pass its gate_owner!).
      class SuggestionsController < BaseController
        include SuggestionPayload

        DEFAULT_LIMIT = 25
        MAX_LIMIT     = 100

        def index
          status = params[:status].to_s.presence || "pending"
          unless Suggestion::STATUSES.include?(status)
            render json: { error: "invalid_status", allowed: Suggestion::STATUSES },
                   status: :unprocessable_entity
            return
          end

          suggestions = Suggestion.where(status: status)
                                  .order(created_at: :asc)
                                  .includes(:user, :subject)
          if params[:restaurant_id].present?
            suggestions = suggestions.where(
              subject_type: "Item",
              subject_id: Item.where(restaurant_id: params[:restaurant_id]).select(:id)
            )
          end

          total  = suggestions.count
          limit  = page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
          offset = page_offset

          render json: {
            suggestions: suggestions.limit(limit).offset(offset).map { |s| suggestion_payload(s) },
            pagination: { total: total, limit: limit, offset: offset }
          }
        end
      end
    end
  end
end
