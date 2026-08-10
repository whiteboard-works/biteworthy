require "rails_helper"
require Rails.root.join("db/migrate/20260810030000_backfill_conversation_run_costs")

# `cost_micro_cents` shipped with a default of 0 and no backfill, so every
# run that predates it reported **0¢ for the turn** beside a real
# conversation total — a contradiction in the very footer that was added
# to remove one. The token split is on each row, so the cost is
# recoverable exactly rather than estimated.
#
# The conversation half is the dangerous half: it rewrites a figure the
# spend ceiling reads, so most of what follows is about the cases where
# it must decline.
RSpec.describe BackfillConversationRunCosts do
  let(:conversation) { Conversation.create!(user: create(:user)) }

  def run_with(rounds: 1, cost: 0, **tokens)
    run = ConversationRun.acquire(conversation)
    run.update_columns(rounds: rounds, cost_micro_cents: cost, **tokens)
    run.release!(outcome: "done")
    run.reload
  end

  def stored_total(cents) = conversation.update_columns(api_cost_micro_cents: cents * 1_000_000)

  # The real 24¢ turn from production: 4 rounds, 26,290 in, 860 out,
  # 30,560 cache read, 7,640 cache write — 21.60¢ of tokens reported as
  # 24¢, because `.cents` rounded up once per model call.
  it "recovers the exact cost from the recorded token split" do
    run = run_with(rounds: 4, input_tokens: 26_290, output_tokens: 860,
                   cache_read_tokens: 30_560, cache_write_tokens: 7_640)
    stored_total(24)

    described_class.new.up

    expected = (26_290 * 500) + (860 * 2_500) + (30_560 * 50) + (7_640 * 625)
    expect(run.reload.cost_micro_cents).to eq(expected)
    expect((expected / 1_000_000.0).round(2)).to eq(21.60)
    expect(conversation.reload.api_cost_cents).to eq(22)
  end

  it "is a no-op on a run that already recorded its own cost" do
    run = run_with(rounds: 1, cost: 999, input_tokens: 1_000)
    stored_total(0)

    described_class.new.up

    expect(run.reload.cost_micro_cents).to eq(999)
    # And the conversation is left alone too: a zero total has nothing to
    # correct, and rewriting it to the run sum would invent spend.
    expect(conversation.reload.api_cost_micro_cents).to eq(0)
  end

  # `record_usage!` has accrued exact micro-cents since the column
  # existed, so those totals carry no rounding to fix. A figure that is
  # not a whole number of cents cannot have come from the rounded
  # backfill, whatever its runs happen to add up to — and here they add
  # up to *less*, which is the case that makes the guard load-bearing
  # rather than decorative: a run row that no longer exists would
  # otherwise silently shrink a correct total.
  it "leaves a total that was never rounded alone, even when its runs total less" do
    run_with(rounds: 2, cost: 6_000_000, input_tokens: 1_000)
    conversation.update_columns(api_cost_micro_cents: 7_400_500)

    described_class.new.up

    expect(conversation.reload.api_cost_micro_cents).to eq(7_400_500)
  end

  # The guard that matters. A conversation older than `conversation_runs`
  # has spend its runs cannot account for, and summing them would erase
  # it. Rounding can only ever have added a cent per model call, so a gap
  # wider than that is not rounding — and the migration must decline
  # rather than guess.
  it "declines when the gap is too wide to be rounding" do
    run_with(rounds: 2, input_tokens: 1_000) # 500,000 µ¢ of tokens
    stored_total(50)                         # 50,000,000 µ¢ stored

    described_class.new.up

    expect(conversation.reload.api_cost_micro_cents).to eq(50 * 1_000_000)
  end

  it "still corrects when the gap is within what rounding explains" do
    run_with(rounds: 2, input_tokens: 3_000) # 1,500,000 µ¢
    stored_total(3)                          # 3,000,000 µ¢ — 1.5M gap, 2 calls

    described_class.new.up

    expect(conversation.reload.api_cost_micro_cents).to eq(1_500_000)
  end

  # Rounding only ever rounds *up*, so a stored total below the runs'
  # sum did not come from rounding and is not this migration's business.
  it "never raises a total" do
    run_with(rounds: 1, cost: 9_000_000, input_tokens: 1_000)
    stored_total(1)

    described_class.new.up

    expect(conversation.reload.api_cost_micro_cents).to eq(1_000_000)
  end
end
