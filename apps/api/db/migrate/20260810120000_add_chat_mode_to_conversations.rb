class AddChatModeToConversations < ActiveRecord::Migration[8.1]
  # How much a conversation has agreed to in advance — see
  # `Chat::ModePolicy`. `manual` is the historical behaviour, so every
  # existing row backfills into exactly what it was already doing.
  #
  # A CHECK constraint alongside the model validation for the same reason
  # `state` has one: the value decides whether a destructive tool call
  # stops for a human, and a jsonb payload written by an older deploy or
  # a console typo must not be able to put `auto` in a column that means
  # "stop asking". The model rejects unknown values, the database refuses
  # to store them, and `ModePolicy.resolve` reads anything unrecognised as
  # `manual` — the strictest of the four.
  #
  # No index. It is read by primary key alongside the rest of the row and
  # nothing filters conversations by mode.
  def change
    add_column :conversations, :chat_mode, :string, null: false, default: "manual"

    add_check_constraint :conversations,
                         "chat_mode IN ('planning', 'manual', 'accept_edits', 'auto')",
                         name: "conversations_chat_mode_valid"
  end
end
