class CreateUserItemOverrides < ActiveRecord::Migration[8.1]
  # Phase 4.2 — persistent "never hide this dish" overrides. Phase 3.4
  # shipped the session-only equivalent; this table makes it durable
  # so the override survives a logout/login cycle.
  #
  # `never_hide` is currently the only mode but lives as a column
  # (not a presence-of-row flag) so a future "always_show_strict" or
  # "always_hide_anyway" mode can land without a migration.
  def change
    create_table :user_item_overrides, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.boolean    :never_hide, null: false, default: true
      t.timestamps
    end
    add_index :user_item_overrides, [:user_id, :item_id], unique: true
  end
end
