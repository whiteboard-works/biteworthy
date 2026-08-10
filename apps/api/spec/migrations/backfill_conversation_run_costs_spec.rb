require "rails_helper"
require Rails.root.join("db/migrate/20260810030000_backfill_conversation_run_costs")

# `cost_micro_cents` shipped with a default of 0 and no backfill, so every
# run that predates it reported **0¢ for the turn** beside a real
# conversation total — a contradiction in the very footer that was added
# to remove one. The token split is on each row, so the cost is
# recoverable exactly rather than estimated.
RSpec.describe BackfillConversationRunCosts do
  let(:conversation) { Conversation.create!(user: create(:user)) }

  def run_with(tokens)
    run = ConversationRun.acquire(conversation)
    run.update_columns(**tokens, cost_micro_cents: 0)
    run.release!(outcome: "done")
    run.reload
  end

  # The real 24¢ turn from production: 4 rounds, 26,290 in, 860 out,
  # 30,560 cache read, 7,640 cache write — 21.60¢ of tokens reported as
  # 24¢, because `.cents` rounded up once per model call.
  it "recovers the exact cost from the recorded token split" do
    run = run_with(input_tokens: 26_290, output_tokens: 860,
                   cache_read_tokens: 30_560, cache_write_tokens: 7_640)
    conversation.update_columns(api_cost_micro_cents: 24 * 1_000_000)

    described_class.new.up

    expected = (26_290 * 500) + (860 * 2_500) + (30_560 * 50) + (7_640 * 625)
    expect(run.reload.cost_micro_cents).to eq(expected)
    expect((expected / 1_000_000.0).round(2)).to eq(21.60)
    # And the conversation total stops carrying the rounding.
    expect(conversation.reload.api_cost_cents).to eq(22)
  end

  it "is a no-op on a run that already recorded its own cost" do
    run = run_with(input_tokens: 1_000, output_tokens: 0,
                   cache_read_tokens: 0, cache_write_tokens: 0)
    run.update_columns(cost_micro_cents: 999)

    described_class.new.up

    expect(run.reload.cost_micro_cents).to eq(999)
  end

  # A conversation whose spend predates `conversation_runs` has nothing to
  # recompute from. Summing over zero token rows would replace a real
  # figure with nothing, which is a worse error than the rounding.
  it "leaves a conversation with no token-carrying runs alone" do
    conversation.update_columns(api_cost_micro_cents: 500 * 1_000_000)
    run_with(input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0)

    described_class.new.up

    expect(conversation.reload.api_cost_micro_cents).to eq(500 * 1_000_000)
  end
end
