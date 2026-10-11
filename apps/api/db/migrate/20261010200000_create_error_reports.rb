# frozen_string_literal: true

# One row per distinct failure the app has reported, with its count and
# the GitHub issue that tracks it. See `ErrorReport` and ADR 0008.
class CreateErrorReports < ActiveRecord::Migration[8.1]
  def change
    create_table :error_reports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :fingerprint, null: false
      t.string   :error_class, null: false
      t.string   :title, null: false
      t.text     :message, null: false
      t.string   :source, null: false
      t.boolean  :handled, null: false, default: true
      t.jsonb    :context, null: false, default: {}
      t.text     :backtrace
      t.integer  :occurrences, null: false, default: 0
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      # The issue filed for this fingerprint, when it was opened, how many
      # occurrences it had been told about, when it was last written to
      # (the hourly write slot), and when a catch-up sync is due.
      t.integer  :issue_number
      t.datetime :issue_opened_at
      t.integer  :issue_occurrences, null: false, default: 0
      t.datetime :issue_touched_at
      t.datetime :sync_scheduled_at
      t.timestamps
    end

    add_index :error_reports, :fingerprint, unique: true
    add_index :error_reports, :last_seen_at
    add_index :error_reports, :issue_opened_at
  end
end
