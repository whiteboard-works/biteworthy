# frozen_string_literal: true

module Tools
  module Suggestions
    class ListSuggestions < Suggestions::Base
      audience :user

      tool_name "list_suggestions"
      title "Read the correction queue"
      description <<~TEXT
        Corrections people have proposed for a restaurant's dishes. Only the
        restaurant's verified owner or an admin can read this queue.

        Defaults to `pending` — the ones still waiting on a decision. Pass
        `status` to see what was already accepted or rejected.

        Each row carries the proposed change in `payload`. Summarize what it
        would do to the dish before the owner resolves it; "add contains-dairy
        to the queso" is a decision they can make, a raw payload is not.
      TEXT

      input_schema(
        properties: {
          restaurant: { type: "string", description: "Restaurant slug or UUID." },
          status: {
            type: "string",
            description: "Which suggestions to return. Default 'pending'.",
            enum: Suggestion::STATUSES
          },
          limit:  { type: "integer", description: "Max rows, 1–100. Default 25." },
          offset: { type: "integer", description: "Rows to skip, for paging." }
        },
        required: ["restaurant"]
      )

      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      DEFAULT_LIMIT = 25
      MAX_LIMIT     = 100

      def self.perform(context:, restaurant:, status: "pending", limit: nil, offset: nil)
        unless Suggestion::STATUSES.include?(status)
          raise Errors::InvalidArgument, "status must be one of: #{Suggestion::STATUSES.join(', ')}."
        end

        record = Restaurant.find_by_id_or_slug!(restaurant)
        authorize_owner!(context, record)

        scope = Suggestion.where(status: status)
                          .where(subject_type: "Item", subject_id: record.items.select(:id))
        page = scope.order(created_at: :asc)
                    .includes(:user, :subject)
                    .offset(clamp_offset(offset))
                    .limit(clamp_limit(limit, default: DEFAULT_LIMIT, max: MAX_LIMIT))

        ok(
          restaurant:  { id: record.id, slug: record.slug, name: record.name },
          status:      status,
          suggestions: page.map { |s| suggestion_row(s) },
          total:       scope.count
        )
      end
    end
  end
end
