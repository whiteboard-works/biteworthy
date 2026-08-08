class CreateMcpTokens < ActiveRecord::Migration[8.1]
  def change
    # A least-privilege credential for an MCP client.
    #
    # The alternative — and what everyone does today — is handing Claude
    # Code the same JWT the web app uses, which carries everything the
    # account can do. A token here names what it may touch.
    create_table :mcp_tokens, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true

      # What the person called it, so a list of tokens is legible and a
      # revocation is an informed decision rather than a guess.
      t.string :name, null: false

      # SHA-256 of the secret. The secret itself is shown once at
      # creation and never stored — a leaked database must not be a
      # leaked set of working credentials.
      t.string :token_digest, null: false

      # Domain-scoped grants (`discovery:read`, `profile:write`, …).
      # Empty means unrestricted, which is what every pre-existing
      # credential effectively was.
      t.string :scopes, array: true, null: false, default: []

      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :mcp_tokens, :token_digest, unique: true
  end
end
