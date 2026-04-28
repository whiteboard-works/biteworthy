class CreateReviewsAndPhotos < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.integer :rating, null: false # 1..5
      t.text    :body
      t.timestamps
    end
    add_index :reviews, [:user_id, :item_id], unique: true
    add_check_constraint :reviews, "rating BETWEEN 1 AND 5", name: "reviews_rating_range"

    # Suggestions queue replaces the 2020 points/levels system.
    # Anyone can propose an edit; admins and claimed-restaurant owners review.
    create_table :suggestions, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: true
      t.references :subject, type: :uuid, polymorphic: true, null: false
      t.string :kind, null: false # add_ingredient | remove_tag | rename | claim | ...
      t.jsonb  :payload, null: false, default: {}
      t.string :status, null: false, default: "pending" # pending | accepted | rejected
      t.references :resolved_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :suggestions, [:subject_type, :subject_id]
    add_index :suggestions, :status
  end
end
