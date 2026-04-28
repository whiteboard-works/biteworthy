class CreateUserProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :user_profiles, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      # Hard filters
      t.uuid :avoid_ingredient_ids, array: true, default: [], null: false
      t.uuid :avoid_tag_ids,        array: true, default: [], null: false

      # Soft sort
      t.uuid :prefer_tag_ids, array: true, default: [], null: false

      # relaxed | balanced | strict
      # In strict mode, items without confirmed=confidence are also hidden.
      t.string :strictness, null: false, default: "balanced"

      t.references :primary_dietary_profile, type: :uuid, foreign_key: { to_table: :dietary_profiles }

      t.timestamps
    end

    add_index :user_profiles, :avoid_ingredient_ids, using: :gin
    add_index :user_profiles, :avoid_tag_ids,        using: :gin
    add_index :user_profiles, :prefer_tag_ids,       using: :gin
  end
end
