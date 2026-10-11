# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ReextractRestaurant do
  let(:user) { create(:user, :admin) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) { create(:ingestion_run, restaurant: restaurant, user: user, status: "staged") }

  before do
    run.inputs.attach(
      io: StringIO.new("fake-bytes"),
      filename: "menu.jpg",
      content_type: "image/jpeg"
    )
  end

  it "dry-run reports the inputs and does not start a scan" do
    expect(Ingestion::StartRun).not_to receive(:call)

    result = described_class.call(restaurant: restaurant, dry_run: true)
    expect(result.ok).to be true
    expect(result.dry_run).to be true
    expect(result.input_count).to eq(1)
    expect(result.run).to be_nil
  end

  it "creates a fresh scan from the latest inputs with no auto-accept" do
    allow(ExtractMenuJob).to receive(:perform_later)

    result = described_class.call(restaurant: restaurant, dry_run: false)
    expect(result.ok).to be true
    expect(result.run).to be_present
    expect(result.run.id).not_to eq(run.id)
    expect(result.run.restaurant).to eq(restaurant)
    expect(result.run.input_kind).to eq("photo")
    expect(result.run.inputs).to be_attached
    expect(result.run.ingestion_items).to be_empty
    expect(ExtractMenuJob).to have_received(:perform_later).with(result.run.id)
  end

  it "fails when the latest run has no inputs" do
    run.inputs.purge
    result = described_class.call(restaurant: restaurant, dry_run: false)
    expect(result.ok).to be false
    expect(result.message).to match(/No inputs/)
  end
end
