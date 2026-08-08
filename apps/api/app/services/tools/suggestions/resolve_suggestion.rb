# frozen_string_literal: true

module Tools
  module Suggestions
    class ResolveSuggestion < Suggestions::Base
      audience :user

      tool_name "resolve_suggestion"
      title "Accept or reject a correction"
      description <<~TEXT
        Decide a pending correction. Accepting APPLIES it to the live dish
        immediately and records it as human-confirmed, which means it outranks
        anything a future menu scan says. Rejecting only closes the row.

        Only the restaurant's verified owner or an admin can decide. Confirm
        with the user before accepting — an accepted `remove_ingredient`
        un-hides that dish for everyone avoiding it, and the person who
        submitted it is a stranger.

        Read the suggestion with `list_suggestions` first and say out loud what
        accepting would change.
      TEXT

      DECISIONS = %w[accepted rejected].freeze

      input_schema(
        properties: {
          suggestion_id: { type: "string", description: "The suggestion's UUID, from list_suggestions." },
          decision:      { type: "string", description: "What to do with it.", enum: DECISIONS }
        },
        required: %w[suggestion_id decision]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false)

      def self.perform(context:, suggestion_id:, decision:)
        user = context.user!
        unless DECISIONS.include?(decision)
          raise Errors::InvalidArgument, "decision must be one of: #{DECISIONS.join(', ')}."
        end

        suggestion = Suggestion.includes(:user, :subject).find(suggestion_id)
        item = suggestion.subject
        raise Errors::InvalidArgument, "That suggestion is not about a dish." unless item.is_a?(Item)
        authorize_owner!(context, item.restaurant)

        apply!(suggestion, decision, user)
        ok(suggestion_row(suggestion.reload))
      rescue SuggestionResolver::InvalidPayloadError, SuggestionResolver::UnsupportedKindError => e
        raise Errors::InvalidArgument, e.message
      end

      def self.apply!(suggestion, decision, user)
        if decision == "accepted"
          SuggestionResolver.accept!(suggestion, by_user: user)
        else
          SuggestionResolver.reject!(suggestion, by_user: user)
        end
      end
      private_class_method :apply!
    end
  end
end
