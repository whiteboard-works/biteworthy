class AddCompactedAtToMessages < ActiveRecord::Migration[8.0]
  # When this message's tool results stopped being sent to the model.
  #
  # A marker rather than a rewrite: the rows keep their full content, so
  # nothing a person can read is lost and the decision is reversible by
  # clearing the column. `Conversation#transcript` is the only reader —
  # it swaps the results for a placeholder on the way to the API.
  #
  # It has to be persisted rather than recomputed per turn. A rule
  # evaluated live would elide a different set as the conversation grew,
  # which changes the bytes above the prompt-cache breakpoint and re-writes
  # the whole transcript on *every* turn — paying the cost this exists to
  # avoid, forever.
  def change
    add_column :messages, :compacted_at, :datetime
  end
end
