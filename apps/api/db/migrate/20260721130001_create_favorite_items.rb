class CreateFavoriteItems < ActiveRecord::Migration[8.1]
  # A user's saved dishes. Mirror of favorite_restaurants — presence of
  # a row = favorited, real FKs so item/user deletion cascades.
  def change
    create_table :favorite_items, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :favorite_items, [:user_id, :item_id], unique: true
  end
end
