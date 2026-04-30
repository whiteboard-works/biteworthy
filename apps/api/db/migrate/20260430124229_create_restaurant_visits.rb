class CreateRestaurantVisits < ActiveRecord::Migration[8.1]
  # Phase 4.8 — "My filtered menus" history.
  #
  # One row per (user, restaurant, day). The unique index makes the
  # visit-recording job an upsert with no race-condition risk — a
  # user reloading the same restaurant five times in a day produces
  # a single row with the latest counts.
  #
  # Counts are denormalized so the History list renders without
  # touching items/reviews (cheap, bounded query). They reflect the
  # LAST visit's state per day, not an average — fine for the use
  # case ("see what I saw").
  def change
    create_table :restaurant_visits, id: :uuid do |t|
      t.references :user,       type: :uuid, null: false, foreign_key: true
      t.references :restaurant, type: :uuid, null: false, foreign_key: true
      t.date       :viewed_on,  null: false
      t.integer    :items_visible_count, null: false, default: 0
      t.integer    :items_hidden_count,  null: false, default: 0
      t.timestamps
    end

    add_index :restaurant_visits, [:user_id, :restaurant_id, :viewed_on], unique: true,
              name: "idx_restaurant_visits_user_restaurant_day"
    # History list reads "the user's recent visits" — a per-user index
    # over updated_at lets us page newest-first without a sort.
    add_index :restaurant_visits, [:user_id, :updated_at], order: { updated_at: :desc },
              name: "idx_restaurant_visits_user_recent"
  end
end
