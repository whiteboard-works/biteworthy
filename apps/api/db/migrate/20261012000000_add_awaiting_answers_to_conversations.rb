class AddAwaitingAnswersToConversations < ActiveRecord::Migration[8.1]
  # The second parked state.
  #
  # `awaiting_confirmation` asks a yes/no about one call the model wants
  # to make. This asks a *question* — "which of these three restaurants
  # did you mean" — and the answer comes back as the id of an option the
  # server wrote down, not as free text the model has to interpret. That
  # is the whole point: "yes" typed into a chat box is a string, and a
  # string is something a model can read the wrong way.
  def up
    add_column :conversations, :pending_questions, :jsonb

    # Rewritten rather than extended: a CHECK constraint has no ALTER that
    # adds a value, and the old one has to go before the new one can name
    # the same column.
    remove_check_constraint :conversations, name: "conversations_state_valid"
    add_check_constraint :conversations,
                         "state IN ('active', 'awaiting_confirmation', 'awaiting_answers', 'failed')",
                         name: "conversations_state_valid"
  end

  def down
    # Postgres validates every existing row when the narrower constraint
    # is added, so a conversation parked on a question would make the
    # rollback itself fail — exactly while someone has an unanswered
    # question open. Those rows go back to `active` with the park cleared:
    # the question is lost, and the person asks again.
    execute <<~SQL
      UPDATE conversations
         SET state = 'active', pending_tool_call = NULL, pending_questions = NULL
       WHERE state = 'awaiting_answers'
    SQL

    remove_check_constraint :conversations, name: "conversations_state_valid"
    add_check_constraint :conversations,
                         "state IN ('active', 'awaiting_confirmation', 'failed')",
                         name: "conversations_state_valid"
    remove_column :conversations, :pending_questions
  end
end
