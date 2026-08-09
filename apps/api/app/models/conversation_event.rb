# frozen_string_literal: true

# One line of a turn's narration, written down instead of only sent.
#
# The stream used to BE the narration: if the socket died, whatever the
# user had not read yet was gone, and all they could do was wait blind for
# the turn to finish and refetch. Persisting each event turns a reconnect
# into a replay — the client sends the last position it saw and picks up
# from there.
#
# Text deltas are coalesced by the writer rather than stored per token; a
# row per token would be tens of thousands of inserts for one answer.
class ConversationEvent < ApplicationRecord
  belongs_to :conversation
  belongs_to :conversation_run

  scope :after, ->(position) { where(position: (position.to_i + 1)..) }
  scope :in_order, -> { order(:position) }

  # How many positions to walk past before giving up. A collision means a
  # second writer beat us to a position, which needs one more try, not
  # five — the bound is here so a pathological loop cannot spin.
  MAX_ATTEMPTS = 5

  INSERT_SQL = <<~SQL.squish.freeze
    INSERT INTO conversation_events (conversation_id, conversation_run_id, position, payload, created_at)
    SELECT ?, ?, COALESCE(MAX(position), 0) + 1, CAST(? AS jsonb), ?
    FROM conversation_events WHERE conversation_id = ?
    ON CONFLICT (conversation_id, position) DO NOTHING
    RETURNING id, position
  SQL
  private_constant :INSERT_SQL

  # Positions are per conversation, not per run, so a client that watched
  # one turn end and the next begin sees one monotonic sequence.
  #
  # The position is chosen *inside* the INSERT rather than read first and
  # written second. The two-statement version had to be serialized, and it
  # was serialized by taking an exclusive lock on the `conversations` row
  # — the same row `Conversation#append!` locks. Narration flushes every
  # 80 characters, so a 4,000-character answer took ~50 of those locks and
  # queued the turn's own message writes behind them.
  #
  # `ON CONFLICT DO NOTHING` is how a genuine race stays cheap: the loser
  # gets no row back rather than an exception, so there is no aborted
  # transaction to unwind and no savepoint to pay for on the happy path.
  def self.append!(run, payload)
    MAX_ATTEMPTS.times do
      row = insert_at_next_position(run, payload)
      return row if row
    end

    raise ActiveRecord::RecordNotUnique,
          "conversation #{run.conversation_id} kept losing the race for an event position"
  end

  def self.insert_at_next_position(run, payload)
    sql = sanitize_sql_array(
      [ INSERT_SQL, run.conversation_id, run.id, payload.to_json, Time.current, run.conversation_id ]
    )
    connection.exec_query(sql, "ConversationEvent Append").first
  end
  private_class_method :insert_at_next_position
end
