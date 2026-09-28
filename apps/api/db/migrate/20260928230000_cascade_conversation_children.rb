# Deleting a chat has to win against a turn that is still writing to it.
# Rails destroys the children one table at a time, so a message, event or
# run inserted between those deletes and the final parent DELETE used to
# block it on a foreign key — the same failure that made every chat
# undeletable. With the keys cascading, the database removes whatever a
# late write left behind as part of the parent delete itself.
class CascadeConversationChildren < ActiveRecord::Migration[8.1]
  CASCADES = [
    %i[conversation_events conversation_runs],
    %i[conversation_events conversations],
    %i[conversation_runs conversations],
    %i[messages conversations]
  ].freeze

  def up
    CASCADES.each do |from, to|
      remove_foreign_key from, to
      add_foreign_key from, to, on_delete: :cascade
    end
  end

  def down
    CASCADES.each do |from, to|
      remove_foreign_key from, to
      add_foreign_key from, to
    end
  end
end
