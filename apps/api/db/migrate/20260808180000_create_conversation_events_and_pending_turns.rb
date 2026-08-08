class CreateConversationEventsAndPendingTurns < ActiveRecord::Migration[8.1]
  def change
    # The narration, as a record rather than as bytes on a socket.
    #
    # A turn takes about a minute, which is long enough for a laptop to
    # close, a proxy to time out, or a deploy to roll. Writing the events
    # down means a reconnect can resume the narration from where it
    # stopped instead of staring at a spinner until the turn ends.
    create_table :conversation_events, id: :uuid do |t|
      t.references :conversation, type: :uuid, null: false, foreign_key: true, index: false
      t.references :conversation_run, type: :uuid, null: false, foreign_key: true, index: false
      # Monotonic per conversation, and what a client sends back as
      # Last-Event-ID to say "carry on from here".
      t.integer :position, null: false
      t.jsonb   :payload, null: false
      t.datetime :created_at, null: false
    end

    add_index :conversation_events, [:conversation_id, :position], unique: true

    # The queue. A message that arrives while a turn holds the lock waits
    # here rather than being dropped or interleaved into the running
    # transcript — the job drains it after releasing.
    add_column :conversations, :pending_turns, :jsonb, null: false, default: []
  end
end
