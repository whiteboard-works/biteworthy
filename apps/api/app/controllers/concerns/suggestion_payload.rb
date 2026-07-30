# Shared suggestion serialization — used by the owner queue
# (SuggestionsController) and the admin cross-restaurant queue so the
# two lists render the same rows.
module SuggestionPayload
  extend ActiveSupport::Concern

  private

  def suggestion_payload(suggestion)
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
