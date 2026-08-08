class CreateConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.string  :title
      # active | awaiting_confirmation | failed. The middle one is the
      # human gate: the loop stops before a destructive tool call and
      # parks it in pending_tool_call until the user says yes.
      t.string  :state, null: false, default: "active"
      t.jsonb   :pending_tool_call
      # Spend accrues here the way IngestionRun.api_cost_cents does, so
      # one ceiling query covers a conversation and one covers the day.
      t.integer :api_cost_cents, null: false, default: 0
      t.timestamps
    end

    add_index :conversations, [:user_id, :updated_at]
    add_index :conversations, :created_at

    create_table :messages, id: :uuid do |t|
      t.references :conversation, type: :uuid, null: false, foreign_key: true, index: false
      t.string  :role, null: false
      # The Anthropic content-block array, stored verbatim. Tool calls,
      # tool results, and thinking blocks all have to travel back into
      # the next request byte-for-byte — a thinking block's signature is
      # rejected if it is reconstructed rather than replayed.
      t.jsonb   :content, null: false, default: []
      t.integer :position, null: false
      t.timestamps
    end

    add_index :messages, [:conversation_id, :position], unique: true

    add_check_constraint :conversations, "state IN ('active', 'awaiting_confirmation', 'failed')",
                         name: "conversations_state_valid"
    add_check_constraint :messages, "role IN ('user', 'assistant')", name: "messages_role_valid"
  end
end
