# An event belongs to its run, so deleting the run should take the events
# with it. Without the cascade, deleting a chat raced any turn still
# writing: an event appended between Rails destroying the events and
# destroying the runs made the run delete fail on this key.
class CascadeConversationEventsOnRunDelete < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :conversation_events, :conversation_runs
    add_foreign_key :conversation_events, :conversation_runs, on_delete: :cascade
  end
end
