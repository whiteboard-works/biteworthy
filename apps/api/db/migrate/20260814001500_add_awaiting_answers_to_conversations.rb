class AddAwaitingAnswersToConversations < ActiveRecord::Migration[8.0]
  # The second parked state.
  #
  # `awaiting_confirmation` asks a yes/no about one call the model wants
  # to make. This asks a *question* — "which of these three restaurants
  # did you mean" — and the answer comes back as the id of an option the
  # server wrote down, not as free text the model has to interpret. That
  # is the whole point: "yes" typed into a chat box is a string, and a
  # string is something a model can read the wrong way.
  def change
    add_column :conversations, :pending_questions, :jsonb

    # Rewritten rather than extended: a CHECK constraint has no ALTER that
    # adds a value, and the old one has to go before the new one can name
    # the same column.
    reversible do |dir|
      dir.up do
        remove_check_constraint :conversations, name: "conversations_state_valid"
        add_check_constraint :conversations,
                             "state IN ('active', 'awaiting_confirmation', 'awaiting_answers', 'failed')",
                             name: "conversations_state_valid"
      end
      dir.down do
        remove_check_constraint :conversations, name: "conversations_state_valid"
        add_check_constraint :conversations,
                             "state IN ('active', 'awaiting_confirmation', 'failed')",
                             name: "conversations_state_valid"
      end
    end
  end
end
