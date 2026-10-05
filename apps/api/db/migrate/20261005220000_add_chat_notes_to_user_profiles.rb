# frozen_string_literal: true

class AddChatNotesToUserProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :user_profiles, :chat_notes, :text
  end
end
