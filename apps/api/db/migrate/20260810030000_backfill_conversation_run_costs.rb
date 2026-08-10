class BackfillConversationRunCosts < ActiveRecord::Migration[8.1]
  # `cost_micro_cents` arrived with a default of 0 and was never
  # backfilled, so every run that predates it reports **0¢ for the turn**
  # next to a real conversation total — a visible contradiction in the
  # footer that was added to remove one.
  #
  # The token split is right there on each row, so the cost is
  # recoverable exactly rather than estimated. Rates are inlined rather
  # than read from `Ingestion::UsageCost`: a migration that calls into
  # app code silently changes meaning when that code does.
  #
  #   claude-opus-5, cents per million tokens:
  #   input 500 · output 2,500 · cache read 50 · cache write 625
  #
  # Single-rate arithmetic is only safe because of the `WHERE` below.
  # A run's token columns can also contain the grounding reviewer's
  # haiku tokens (`record_side_call!`), which bill at a fifth of these
  # rates — but `record_side_call!` and `cost_micro_cents` shipped in the
  # same change, so every run carrying reviewer tokens already has a
  # non-zero cost and is skipped. The rows this touches predate the
  # reviewer entirely and are pure opus-5.
  RATES = "input_tokens * 500 + output_tokens * 2500 + " \
          "cache_read_tokens * 50 + cache_write_tokens * 625"

  def up
    execute <<~SQL.squish
      UPDATE conversation_runs SET cost_micro_cents = #{RATES}
      WHERE cost_micro_cents = 0
    SQL

    backfill_conversation_totals
  end

  # No `down`: the pre-migration values were the rounded ones this
  # replaces, and restoring a worse number is not a rollback anyone wants.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Conversation totals were carried over as `api_cost_cents × 1e6`, so
  # they preserve the per-call rounding this arc exists to remove — 203¢
  # standing in for 190.51¢ of tokens.
  #
  # Three guards, each closing a way this could turn right data wrong.
  #
  # **Summed from `cost_micro_cents`, not re-derived from tokens.** After
  # the statement above that column is correct for every run, priced at
  # whichever model actually served the call — and it also carries the
  # lost-lease charges that `raise_lost_lease!` records *without* tokens,
  # on purpose, so the daily ceiling keeps its teeth. Re-deriving from
  # token columns would price haiku at opus rates and silently drop that
  # money.
  #
  # **Only totals that are an exact multiple of 1,000,000.** That is the
  # signature of the rounded backfill; a real accrual lands on a cent
  # boundary about one time in a million. It is belt-and-braces rather
  # than load-bearing — for a conversation accrued after `record_usage!`
  # went exact, the sum of its runs *equals* its total, because both add
  # up the same calls — but it keeps the statement from touching rows it
  # has no business rewriting.
  #
  # **And the correction may only remove what rounding could have added.**
  # `.cents` rounds up at most one cent per model call, so the whole
  # possible inflation is bounded by the number of calls. If the gap is
  # bigger than that, the total contains spend the runs do not account
  # for — a conversation older than the `conversation_runs` table, say —
  # and re-deriving would erase it. `SUM(rounds)` under-counts calls
  # slightly (a grounded turn makes an extra one), which makes the bound
  # conservative: it refuses in the ambiguous case rather than guessing.
  def backfill_conversation_totals
    execute <<~SQL.squish
      UPDATE conversations c
      SET api_cost_micro_cents = totals.exact
      FROM (
        SELECT conversation_id,
               SUM(cost_micro_cents) AS exact,
               SUM(rounds)           AS calls
        FROM conversation_runs
        GROUP BY conversation_id
      ) AS totals
      WHERE c.id = totals.conversation_id
        AND totals.exact > 0
        AND c.api_cost_micro_cents % 1000000 = 0
        AND c.api_cost_micro_cents >= totals.exact
        AND c.api_cost_micro_cents - totals.exact <= totals.calls * 1000000
    SQL
  end
end
