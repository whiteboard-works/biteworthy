class DropUnusedColumnsAndIndexes < ActiveRecord::Migration[8.1]
  def change
    # Exact duplicate: same table, same two columns, different name.
    remove_index :suggestions, %i[subject_type subject_id],
                 name: "index_suggestions_on_subject"

    # user_profiles rows are only ever loaded by user_id — nothing
    # queries these arrays with `&&` or any other indexable operator,
    # so all three GIN indexes cost writes and buy nothing. (The GIN
    # indexes on items.ingredient_ids / items.tag_ids DO have a
    # consumer — Cities::RestaurantRanking — and stay.)
    remove_index :user_profiles, :avoid_ingredient_ids, using: :gin,
                 name: "index_user_profiles_on_avoid_ingredient_ids"
    remove_index :user_profiles, :avoid_tag_ids, using: :gin,
                 name: "index_user_profiles_on_avoid_tag_ids"
    remove_index :user_profiles, :prefer_tag_ids, using: :gin,
                 name: "index_user_profiles_on_prefer_tag_ids"

    # Superseded by api_cost_cents, which is what every reader and the
    # daily-spend cap actually use. Never written, so always 0.
    remove_column :ingestion_runs, :cost_cents, :integer, default: 0
    # Never written by any code path, so always the {} default.
    remove_column :ingestion_runs, :raw_output, :jsonb, default: {}

    # cities.latitude / longitude are NOT dropped. No code reads them
    # today, but a pre-merge audit found Durango's real coordinates
    # sitting in them — someone seeded that on purpose, and a city
    # centroid is what a future "near me" would key off. Unread is not
    # the same as empty.

    # Devise :confirmable and :trackable are deliberately not enabled
    # (see the comment in app/models/user.rb) so these have never held
    # a value. `confirmed_at` is NOT dropped — User.from_omniauth
    # writes it to record that the provider verified the address.
    # :rememberable IS enabled, so remember_created_at stays too.
    remove_column :users, :confirmation_token, :string
    remove_column :users, :confirmation_sent_at, :datetime
    remove_column :users, :unconfirmed_email, :string
    remove_column :users, :sign_in_count, :integer, default: 0, null: false
    remove_column :users, :current_sign_in_at, :datetime
    remove_column :users, :last_sign_in_at, :datetime

    # devise-jwt's JTIMatcher revocation strategy uses `jti` alone.
    remove_column :users, :jti_expires_at, :datetime
  end
end
