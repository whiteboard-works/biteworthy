class AddCreatedAtIndexToConversationRuns < ActiveRecord::Migration[8.1]
  # The chat's daily spend ceiling now sums `cost_micro_cents` over the
  # runs that happened today, which is a range scan on `created_at`
  # alone. The existing index is `(conversation_id, created_at)` and
  # cannot serve that — `created_at` is not its leading column.
  #
  # Read once per turn rather than once per round (#555), so it is not
  # hot, but it grows with every run ever taken and the identical
  # sequential scan on `ingestion_runs` was already worth closing
  # (#556). Same fix, before it is a problem rather than after.
  def change
    add_index :conversation_runs, :created_at
  end
end
