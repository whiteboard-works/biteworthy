class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      ## Devise: database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable (kept minimal — no IPs by default for privacy)
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at

      ## Confirmable
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email

      ## Profile basics
      t.string :display_name
      t.string :handle, null: false # public username, unique

      ## OAuth (Apple + Google)
      t.string :provider
      t.string :uid

      ## JWT denylist (jti = unique token id, revoked on logout)
      t.string   :jti, null: false
      t.datetime :jti_expires_at

      t.timestamps
    end

    add_index :users, :email,                unique: true
    add_index :users, :handle,               unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token,   unique: true
    add_index :users, [:provider, :uid],     unique: true
    add_index :users, :jti,                  unique: true
  end
end
