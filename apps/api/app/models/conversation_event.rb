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

  # Positions are per conversation, not per run, so a client that watched
  # one turn end and the next begin sees one monotonic sequence.
  #
  # Locked for the whole insert for the same reason `Message#append!` is:
  # reading the max and then inserting are two statements, and two writers
  # between them collide on the unique index.
  def self.append!(run, payload)
    conversation = run.conversation
    conversation.with_lock do
      create!(
        conversation:     conversation,
        conversation_run: run,
        position:         where(conversation_id: conversation.id).maximum(:position).to_i + 1,
        payload:          payload,
        created_at:       Time.current
      )
    end
  end
end
