# frozen_string_literal: true

# Spell out the authority every unscoped token was already exercising.
#
# `Tools::Scopes.satisfied?` used to treat an empty grant as unrestricted,
# so a token with `scopes = '{}'` could reach all thirteen gated domains.
# That branch is gone and empty now means empty, which would revoke every
# such token the moment the new code took traffic. Nothing here changes
# what a token can do — it writes down what it could do all along.
#
# **Safe in both directions, unlike a column drop.** This only edits data,
# and `'{*}'` reads the same to old code (`list.include?(ALL)`) as to new,
# so the release that runs it does not need a predecessor: during the
# kamal-proxy window the old container honours the backfilled value
# exactly as the new one does.
#
# Deliberately not scoped to `active` tokens. The model now validates
# `scopes` presence, so an empty row that survived here could not be saved
# at all — `revoke!` on an expired token would fail validation on a column
# nobody touched.
class NameFullAccessOnUnscopedMcpTokens < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL.squish)
      UPDATE mcp_tokens SET scopes = '{*}' WHERE scopes = '{}'
    SQL
  end

  # Not reversible: `'{}'` and `'{*}'` mean the same thing to the code
  # this replaces, so there is nothing to restore — and rolling back to a
  # blank grant would re-arm the fail-open rather than undo a change.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
