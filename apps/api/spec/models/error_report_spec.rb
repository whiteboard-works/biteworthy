# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReport do
  include ActiveSupport::Testing::TimeHelpers

  let(:payload) { ErrorReports::Capture.call(RuntimeError.new("boom"), context: { component: "chat" }) }

  it "counts repeats on one row and keeps the first-seen details" do
    first = travel_to(Time.zone.parse("2026-10-10 12:00")) { described_class.record!(payload) }
    later = travel_to(Time.zone.parse("2026-10-10 13:00")) do
      described_class.record!(payload.merge("message" => "changed", "occurrences" => 4))
    end

    expect(later.id).to eq(first.id)
    expect(later.occurrences).to eq(5)
    expect(later.message).to eq("boom")
    expect(later.first_seen_at).to eq(Time.zone.parse("2026-10-10 12:00"))
    expect(later.last_seen_at).to eq(Time.zone.parse("2026-10-10 13:00"))
    expect(later.context).to eq("component" => "chat")
  end

  it "hands out the issue slot once per interval, and takes it back when released" do
    report = described_class.record!(payload)

    expect(report.claim_issue_slot!(interval: 1.hour)).to be(true)
    expect(described_class.find(report.id).claim_issue_slot!(interval: 1.hour)).to be(false)

    report.release_issue_slot!(to: nil)
    expect(described_class.find(report.id).claim_issue_slot!(interval: 1.hour)).to be(true)

    travel 2.hours do
      expect(described_class.find(report.id).claim_issue_slot!(interval: 1.hour)).to be(true)
    end
  end

  it "books one catch-up sync at a time, and another once that time has passed" do
    report = described_class.record!(payload)

    expect(report.claim_issue_slot!(interval: 1.hour)).to be(true)
    expect(report.unreported?).to be(true)
    expect(report.schedule_sync!(at: 1.hour.from_now)).to be(true)
    expect(described_class.find(report.id).schedule_sync!(at: 1.hour.from_now)).to be(false)

    travel 2.hours do
      expect(described_class.find(report.id).schedule_sync!(at: 1.hour.from_now)).to be(true)
    end
  end
end
