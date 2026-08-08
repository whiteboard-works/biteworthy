# frozen_string_literal: true

# OAuth 2.1 authorization server (M8), so an MCP client can be granted
# access without a person pasting a long-lived credential.
#
# Two deviations from doorkeeper's generated migration, both forced by
# this codebase rather than chosen:
#
#   * **uuid throughout.** `users.id` is a uuid, so `resource_owner_id`
#     has to be one; making the doorkeeper tables match keeps every id in
#     the schema the same shape.
#   * **`secret` is nullable and `confidential` defaults to false.** An
#     MCP client is a public client — a desktop app cannot keep a secret —
#     so PKCE is the protection, not a client password.
class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications, id: :uuid do |t|
      t.string  :name,         null: false
      t.string  :uid,          null: false
      t.string  :secret
      t.text    :redirect_uri, null: false
      t.string  :scopes,       null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.timestamps null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants, id: :uuid do |t|
      t.references :resource_owner, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :application,    null: false, type: :uuid
      t.string   :token,        null: false
      t.integer  :expires_in,   null: false
      t.text     :redirect_uri, null: false
      t.string   :scopes,       null: false, default: ""
      t.datetime :created_at,   null: false
      t.datetime :revoked_at
      # PKCE. Required for every grant here — see the initializer.
      t.string   :code_challenge
      t.string   :code_challenge_method
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id

    create_table :oauth_access_tokens, id: :uuid do |t|
      t.references :resource_owner, type: :uuid, index: true, foreign_key: { to_table: :users }
      t.references :application,    null: false, type: :uuid
      t.string   :token,         null: false
      t.string   :refresh_token
      t.integer  :expires_in
      t.string   :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string   :previous_refresh_token, null: false, default: ""
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
  end
end
