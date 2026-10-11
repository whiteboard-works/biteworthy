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

  # The observation is the measurement, never the thing measured: a
  # row that cannot be written must not fail a gap-fill or a chat turn.
  it "drops a row it cannot write instead of raising" do
    allow(Rails.logger).to receive(:warn)

    expect(described_class.note(kind: "not-a-kind", outcome: "answered")).to be_nil
    expect(Rails.logger).to have_received(:warn).with(/observation not saved/)
    expect(described_class.count).to eq(0)
  end
end
