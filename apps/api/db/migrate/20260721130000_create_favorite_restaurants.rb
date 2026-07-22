class CreateFavoriteRestaurants < ActiveRecord::Migration[8.1]
  # A user's saved restaurants. Presence of a row = favorited; there is
  # no mode column (unlike user_item_overrides), so unfavoriting just
  # deletes the row. Real FKs so restaurant/user deletion cascades at
  # the DB level (see the E2 integrity note in user.rb).
  def change
    create_table :favorite_restaurants, id: :uuid do |t|
      t.references :user,       type: :uuid, null: false, foreign_key: true
      t.references :restaurant, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :favorite_restaurants, [:user_id, :restaurant_id], unique: true
  end
end
