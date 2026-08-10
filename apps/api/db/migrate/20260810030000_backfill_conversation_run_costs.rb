class BackfillConversationRunCosts < ActiveRecord::Migration[8.1]
  # `cost_micro_cents` arrived with a default of 0 and was never
  # backfilled, so every run that predates it reports **0¢ for the turn**
  # next to a real conversation total — a visible contradiction in the
  # footer that was added to remove one.
  #
  # The token split is right there on each row, so the cost is
  # recoverable exactly rather than estimated. Rates are inlined rather
  # than read from `Ingestion::UsageCost`: a migration that calls into
  # app code silently changes meaning when that code does, and these runs
  # were billed at *these* rates — cents per million tokens for
  # claude-opus-5, the chat's only model.
  #
  #   input 500 · output 2,500 · cache read 50 · cache write 625
  #
  # `WHERE cost_micro_cents = 0` so a re-run is a no-op and a row that
  # already recorded its own cost is never doubled.
  RATES = "input_tokens * 500 + output_tokens * 2500 + " \
          "cache_read_tokens * 50 + cache_write_tokens * 625"

  def up
    execute <<~SQL.squish
      UPDATE conversation_runs SET cost_micro_cents = #{RATES}
      WHERE cost_micro_cents = 0
    SQL

    # And the conversation totals, which were carried over from the
    # rounded cents column and so preserve the per-call inflation this
    # arc exists to remove — 203¢ for 190.51¢ of tokens, 24¢ for 21.60¢.
    #
    # Only where the conversation actually has runs carrying tokens.
    # A conversation whose spend predates `conversation_runs` has nothing
    # to recompute from, and replacing its total with a sum over zero
    # rows would erase a real figure to fix a rounding error.
    execute <<~SQL.squish
      UPDATE conversations c
      SET api_cost_micro_cents = totals.exact
      FROM (
        SELECT conversation_id, SUM(#{RATES}) AS exact
        FROM conversation_runs
        GROUP BY conversation_id
        HAVING SUM(input_tokens + output_tokens + cache_read_tokens + cache_write_tokens) > 0
      ) AS totals
      WHERE c.id = totals.conversation_id
    SQL
  end

  # No `down`: the pre-migration values were the rounded ones this
  # replaces, and restoring a worse number is not a rollback anyone wants.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
