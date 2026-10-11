require "rails_helper"

RSpec.describe JevObservation do
  let(:run) { create(:ingestion_run, :staged) }

  it "keeps what a call said, attached to what it was about" do
    row = described_class.note(kind: "cuisine", subject: run, model: "jev-1.13.0", latency_ms: 150,
                               input_tokens: 2_000, outcome: "answered", details: { items: 10, tagged: 7 })

    expect(row).to be_persisted
    expect(row.subject).to eq(run)
    expect(row.details).to eq("items" => 10, "tagged" => 7)
    expect(described_class.where(kind: "cuisine").group(:outcome).count).to eq("answered" => 1)
  end

  # The spend and the missed-wheat count were real; cleaning up the run
  # must not erase them from last week's tiles.
  it "outlives its owner with both subject columns nulled, and still counts in the metrics" do
    row = described_class.note(kind: "cuisine", subject: run, outcome: "answered", input_tokens: 700,
                               details: { items: 5, tagged: 2 })
    run.destroy!

    expect(row.reload).to have_attributes(subject_type: nil, subject_id: nil)
    expect(Ingestion::JevMetrics.by_period.fetch(:today).to_h).to include(calls: 1, input_tokens: 700)
  end

  # The observation is the measurement, never the thing measured: a
  # row that cannot be written must not fail a gap-fill or a chat turn.
  it "drops a row it cannot write instead of raising" do
    allow(Rails.logger).to receive(:warn)

    expect(described_class.note(kind: "not-a-kind", outcome: "answered")).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/observation not saved/)
    expect(described_class.count).to eq(0)
  end
end
