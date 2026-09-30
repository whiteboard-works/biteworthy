# frozen_string_literal: true

# What the chat's results pane was last pointed at — a small reference
# (`kind`, ids, counts) the loop writes after each successful tool call, so
# reopening a chat restores the pane without replaying the turn.
class AddLastPaneToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :last_pane, :jsonb
  end
end
