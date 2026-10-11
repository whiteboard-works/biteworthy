# frozen_string_literal: true

# One row per Jev call, live or shadow, so what the model said survives a
# deploy. The cuisine trial's log lines did not: 13 of 16 runs were gone
# with their containers before anyone read them. See `JevObservation`.
class CreateJevObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :jev_observations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :kind, null: false
      t.string   :subject_type
      t.uuid     :subject_id
      t.string   :model
      t.integer  :latency_ms
      t.integer  :input_tokens
      t.string   :outcome, null: false
      # Shadow trials only: did Jev agree with the model it shadows?
      t.boolean  :agree
      t.jsonb    :details, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :jev_observations, [ :kind, :created_at ]
    add_index :jev_observations, [ :subject_type, :subject_id ]
  end
end
