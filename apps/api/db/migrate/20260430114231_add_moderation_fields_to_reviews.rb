class AddModerationFieldsToReviews < ActiveRecord::Migration[8.1]
  # Phase 4.6 — moderation queue.
  #
  # `hidden_at` set ⇒ the review is removed from the public feed.
  # `hidden_reason` records the moderator's reason (spam | abuse |
  # duplicate | off_topic) so we can audit later.
  # `flagged_at` is set by the spam heuristic on save — moderators
  # see flagged reviews in the queue but the public still sees them
  # until a human acts. Cleared once a moderator decides either way.
  #
  # All three are nullable; absence is the happy path.
  def change
    add_column :reviews, :hidden_at,     :datetime
    add_column :reviews, :hidden_reason, :string
    add_column :reviews, :flagged_at,    :datetime

    # Indexes for the two scopes the API + Avo will hit constantly:
    # public feed needs `hidden_at IS NULL`, moderation queue needs
    # `flagged_at IS NOT NULL AND hidden_at IS NULL`.
    add_index :reviews, :hidden_at,  where: "hidden_at IS NOT NULL"
    add_index :reviews, :flagged_at, where: "flagged_at IS NOT NULL AND hidden_at IS NULL"
  end
end
