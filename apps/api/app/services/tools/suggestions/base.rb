# frozen_string_literal: true

module Tools
  module Suggestions
    # Shared owner-gating and serialization for the suggestion queue.
    #
    # A suggestion is a proposed edit to somebody else's menu data, so
    # "who may resolve it" is the whole security model: the restaurant's
    # verified owner, or an admin. `audience :user` is only the outer
    # gate — `authorize_owner!` is the real one.
    class Base < Tools::Base
      audience :user

      class << self
        def authorize_owner!(context, restaurant)
          user = context.user!
          return restaurant if user.is_admin?
          return restaurant if restaurant.claimed_by_user_id.present? &&
                               restaurant.claimed_by_user_id == user.id

          raise Errors::Forbidden,
                "Only the verified owner of #{restaurant.name} can resolve suggestions for it."
        end

        def suggestion_row(suggestion)
          item = suggestion.subject
          {
            id:          suggestion.id,
            kind:        suggestion.kind,
            status:      suggestion.status,
            payload:     suggestion.payload,
            created_at:  suggestion.created_at,
            resolved_at: suggestion.resolved_at,
            dish:        item.is_a?(Item) ? { id: item.id, name: untrusted(item.name) } : nil,
            submitter:   suggestion.user&.handle
          }.compact
        end
      end
    end
  end
end
