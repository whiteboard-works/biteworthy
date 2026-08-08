class CreateConversationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_runs, id: :uuid do |t|
      t.references :conversation, type: :uuid, null: false, foreign_key: true, index: false

      # Ownership. Every lease refresh is a conditional UPDATE matched on
      # this, so a run that lost its lease writes nothing when it comes
      # back — it learns it was replaced instead of clobbering the
      # replacement.
      t.uuid :run_token, null: false

      t.string :state, null: false, default: "running"

      # There is no Redis in this stack. A partial unique index is the
      # mutex and this column is the lease: a worker that dies holding the
      # lock stops refreshing, and the next turn steals it once it lapses.
      t.datetime :lease_expires_at, null: false

      # Set by the stop button. Read at every tick, and compared against
      # started_at so a flag raised for an earlier run can never abort a
      # newer one.
      t.datetime :abort_requested_at

      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string   :outcome
      t.integer  :duration_ms

      # Per-round cost detail. api_cost_cents on the conversation answers
      # "are we over budget"; these answer "what is the money going to",
      # which is what decides whether tool routing or shorter answers is
      # the lever worth pulling.
      t.integer :rounds,             null: false, default: 0
      t.integer :input_tokens,       null: false, default: 0
      t.integer :output_tokens,      null: false, default: 0
      t.integer :cache_read_tokens,  null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0

      t.timestamps
    end

    # The mutex. One running row per conversation; a second acquire hits
    # this and loses rather than interleaving two transcripts.
    add_index :conversation_runs, :conversation_id,
              unique: true, where: "state = 'running'",
              name: "index_conversation_runs_running_unique"
    add_index :conversation_runs, [:conversation_id, :created_at]
    add_index :conversation_runs, :run_token, unique: true

    add_check_constraint :conversation_runs,
                         "state IN ('running', 'done', 'failed', 'aborted', 'lost_lease')",
                         name: "conversation_runs_state_valid"
  end
end
