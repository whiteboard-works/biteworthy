require "rails_helper"

RSpec.describe Ingestion::JevMetrics do
  let(:run)   { create(:ingestion_run, :staged) }
  let(:other) { create(:ingestion_run, :staged) }

  before do
    JevObservation.note(kind: "cuisine", subject: run, outcome: "answered", input_tokens: 2_000,
                        details: { items: 10, tagged: 7, no_cuisine: 2, missing: 0 })
    JevObservation.note(kind: "cuisine", subject: run, outcome: "failed", input_tokens: nil,
                        details: { items: 10, error: "TypesafeClient::ApiError", status: 503 })
    JevObservation.note(kind: "hidden_wheat_shadow", subject: run, outcome: "answered", agree: false,
                        input_tokens: 500, details: { items: 10, agree: 8, jev_only: 2, data_only: 0 })
    JevObservation.note(kind: "hidden_wheat_shadow", subject: other, outcome: "partial", agree: nil,
                        input_tokens: 400, details: { items: 10, agree: 5, jev_only: 0, data_only: 1, missing: 4 })
    JevObservation.note(kind: "cuisine", subject: other, outcome: "answered", input_tokens: 1_000,
                        details: { items: 5, tagged: 3, no_cuisine: 0, missing: 0 }, created_at: 10.days.ago)
  end

  it "buckets calls, outcomes, tokens and the kinds' own counters by the dashboard's periods" do
    today = described_class.by_period.fetch(:today)
    expect(today.to_h).to include(label: "Today", calls: 4, answered: 2, partial: 1, failed: 1, input_tokens: 2_900)
    expect(today.cuisine).to eq(calls: 2, failed: 1, tagged: 7, no_cuisine: 2)
    expect(today.wheat).to eq(calls: 2, agree: 0, disagree: 1, jev_only: 2, data_only: 1)

    month = described_class.by_period.fetch(:last_30_days)
    expect(month.calls).to eq(5)
    expect(month.cuisine[:tagged]).to eq(10)
  end

  # $0.042 per million input tokens, output free: 2,900 tokens is a
  # hundredth of a cent, and the tile must say so rather than round to 0.
  it "prices input tokens at TypeSafe's rate without rounding them away" do
    expect(described_class.by_period.fetch(:today).cost_cents).to eq(0.012)
  end

  it "rolls up per run in one query, naming the wheat disagreements that matter" do
    rollup = described_class.for_runs([ run.id, other.id, SecureRandom.uuid ])

    expect(rollup[run.id]).to eq(calls: 3, failed: 1, input_tokens: 2_500, wheat_jev_only: 2)
    expect(rollup[other.id]).to eq(calls: 2, failed: 0, input_tokens: 1_400, wheat_jev_only: 0)
    expect(rollup[SecureRandom.uuid]).to eq(calls: 0, failed: 0, input_tokens: 0, wheat_jev_only: 0)
    expect(described_class.for_runs([])[run.id]).to eq(calls: 0, failed: 0, input_tokens: 0, wheat_jev_only: 0)
  end

  # `details` is written by several services; one bad value must not 500
  # the dashboard, it is just not counted.
  it "ignores a counter that is not a JSON number instead of raising" do
    JevObservation.note(kind: "hidden_wheat_shadow", subject: run, outcome: "answered", agree: false,
                        details: { items: 1, jev_only: "two" })

    expect(described_class.by_period.fetch(:today).wheat[:jev_only]).to eq(2)
    expect(described_class.for_runs([ run.id ])[run.id][:wheat_jev_only]).to eq(2)
  end
end
