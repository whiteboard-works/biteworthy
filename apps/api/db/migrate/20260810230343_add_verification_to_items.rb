class AddVerificationToItems < ActiveRecord::Migration[8.0]
  def change
    add_column :items, :human_verified_at, :datetime, null: true
    add_column :items, :human_verified_by_user_id, :uuid, null: true
    add_column :items, :restaurant_verified_at, :datetime, null: true
    add_column :items, :restaurant_verified_by_user_id, :uuid, null: true

    add_foreign_key :items, :users, column: :human_verified_by_user_id
    add_foreign_key :items, :users, column: :restaurant_verified_by_user_id

    add_index :items, :human_verified_at
    add_index :items, :restaurant_verified_at
  end
end
