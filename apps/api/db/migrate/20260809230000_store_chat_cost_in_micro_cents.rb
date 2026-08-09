class StoreChatCostInMicroCents < ActiveRecord::Migration[8.1]
  # `UsageCost.cents` rounds UP to the next cent, per model call. That is
  # the right call for ingestion, where a run is one or two calls and a
  # guardrail should overstate — its header comment says so. It is the
  # wrong call for chat, where `AgentLoop#drive` makes up to twelve calls
  # in a single turn and each one independently rounds up: a turn can
  # accrue **12¢ of pure rounding** against a 200¢ ceiling, which is 6%
  # of the cap spent on arithmetic rather than tokens.
  #
  # Micro-cents are exact and free: `UsageCost` already computes
  # `tokens × cents-per-MTok` and then divides by 1e6, so the pre-division
  # integer *is* the micro-cent count. Nothing is estimated here; the
  # rounding is simply deferred to the one place it is displayed.
  #
  # `api_cost_cents` comes back as a GENERATED STORED column rather than a
  # second number the code has to remember to keep in step. Two columns
  # holding the same fact is how they drift, and this table is read by a
  # spend ceiling — a stale cents column would mean either a chat that
  # refuses early or one that never refuses. Postgres computes it, no
  # code can write it, and a console or dashboard reading
  # `api_cost_cents` keeps working unchanged.
  def up
    add_column :conversations, :api_cost_micro_cents, :bigint, null: false, default: 0
    execute <<~SQL.squish
      UPDATE conversations SET api_cost_micro_cents = api_cost_cents::bigint * 1000000
    SQL
    remove_column :conversations, :api_cost_cents
    add_column :conversations, :api_cost_cents, :virtual, type: :integer,
               as: "round(api_cost_micro_cents / 1000000.0)", stored: true

    # Per-run cost, so the UI can say what *this turn* cost next to what
    # the conversation has cost. There was no per-run figure at all
    # before, which is why the footer put a lifetime "203¢ total" beside
    # per-run token counts and read as a contradiction.
    add_column :conversation_runs, :cost_micro_cents, :bigint, null: false, default: 0
  end

  def down
    remove_column :conversation_runs, :cost_micro_cents
    remove_column :conversations, :api_cost_cents
    add_column :conversations, :api_cost_cents, :integer, null: false, default: 0
    execute <<~SQL.squish
      UPDATE conversations SET api_cost_cents = round(api_cost_micro_cents / 1000000.0)
    SQL
    remove_column :conversations, :api_cost_micro_cents
  end
end
