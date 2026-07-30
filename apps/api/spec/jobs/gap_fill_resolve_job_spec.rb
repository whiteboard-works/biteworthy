require "rails_helper"

RSpec.describe GapFillResolveJob, type: :job do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) do
    create(:ingestion_run, :staged, restaurant: restaurant, enrichment_status: "pending")
  end

  before do
    create(:ingredient, slug: "meat-beef") # alias: steak
    create(:ingredient, slug: "fish-anchovy", name: "Anchovy", path: "fish.anchovy", aliases: [])
    create(:tag, slug: "italian", name: "Italian", family: "cuisine", path: "cuisine.italian")
  end

  # As ResolveItemsJob leaves a gap item: pending, empty payloads.
  let!(:gap_item) do
    create(:ingestion_item, ingestion_run: run, position: 0, name: "Caesar Salad",
           description: nil, decision: "pending",
           ingredients_payload: [], tags_payload: [])
  end

  # Fully matched by the deterministic pass — must not be re-sent.
  let!(:matched_item) do
    create(:ingestion_item, ingestion_run: run, position: 1, name: "Steak",
           description: "steak", decision: "pending",
           ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.95, "source" => "match" }],
           tags_payload: [])
  end

  let(:response) do
    { "items" => [
      { "index" => 0,
        "ingredients" => {
          "resolved" => [
            { "slug" => "fish-anchovy", "confidence" => 0.85 },
            { "slug" => "not-a-real-slug", "confidence" => 0.9 },
          ],
          "unresolved" => ["romaine hearts"] },
        "cuisine_tags" => {
          "resolved" => [
            { "slug" => "italian", "confidence" => 0.8 },
            { "slug" => "not-a-cuisine", "confidence" => 0.7 },
          ],
          "unresolved" => ["trattoria style"] } },
    ] }
  end

  describe "the merge" do
    before do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create).and_return(response)
      allow(Rails.logger).to receive(:warn)
    end

    it "appends validated AI ingredients, dropping unknown slugs" do
      described_class.perform_now(run.id)

      payload = gap_item.reload.ingredients_payload
      expect(payload).to contain_exactly(
        { "slug" => "fish-anchovy", "confidence" => 0.85, "source" => "ai" }
      )
      expect(Rails.logger).to have_received(:warn).with(/not-a-real-slug/)
    end

    it "re-derives allergen tags in code from the AI ingredients and appends AI cuisine" do
      described_class.perform_now(run.id)

      tags = gap_item.reload.tags_payload
      expect(tags).to include(
        { "slug" => "contains-fish", "confidence" => 0.85, "source" => "ai" },
        { "slug" => "italian", "confidence" => 0.8, "source" => "ai" }
      )
      expect(tags.map { |t| t["slug"] }).not_to include("not-a-cuisine")
    end

    it "records unresolved strings for the curation queue" do
      described_class.perform_now(run.id)

      gap_item.reload
      expect(gap_item.unresolved_ingredients).to eq(["romaine hearts"])
      expect(gap_item.unresolved_tags).to eq(["trattoria style"])
    end

    it "marks enrichment completed and leaves non-gap items untouched" do
      expect { described_class.perform_now(run.id) }
        .not_to change { matched_item.reload.attributes }

      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "only sends gap items to the model" do
      captured = nil
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do |_, **kwargs|
        captured = kwargs[:messages]
        response
      end

      described_class.perform_now(run.id)

      text = captured.first[:content].first[:text]
      expect(text).to include("Caesar Salad")
      expect(text).not_to include("Steak")
    end

    it "skips an item that got accepted after the gap set was computed" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create) do
        gap_item.update!(decision: "accepted")
        response
      end

      described_class.perform_now(run.id)

      expect(gap_item.reload.ingredients_payload).to eq([])
      expect(run.reload.enrichment_status).to eq("completed")
    end
  end

  describe "soft failure" do
    it "ApiError marks enrichment failed but the run stays staged" do
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ApiError.new(status: 500, body: "boom"))
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(run.id)

      run.reload
      expect(run.status).to eq("staged")
      expect(run.enrichment_status).to eq("failed")
      expect(run.failure_message).to be_nil
      expect(Rails.logger).to have_received(:error).with(/gap_fill_api_error/)
    end

    it "ValidationError still accrues the billed usage" do
      usage = { "input_tokens" => 10_000, "output_tokens" => 100,
                "cache_read_input_tokens" => 0, "cache_creation_input_tokens" => 0 }
      allow_any_instance_of(AnthropicClient).to receive(:messages_create)
        .and_raise(AnthropicClient::ValidationError.new(raw_body: "x", errors: ["bad"]))
      allow_any_instance_of(AnthropicClient).to receive(:last_usage).and_return(usage)
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(run.id) }
        .to change { run.reload.uncached_input_tokens }.by(10_000)

      expect(run.enrichment_status).to eq("failed")
    end
  end

  describe "guards" do
    it "completes without an API call when no pending gaps remain" do
      gap_item.update!(decision: "rejected")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      described_class.perform_now(run.id)

      expect(run.reload.enrichment_status).to eq("completed")
    end

    it "is a no-op when enrichment already completed" do
      run.update!(enrichment_status: "completed")
      expect_any_instance_of(AnthropicClient).not_to receive(:messages_create)

      expect { described_class.perform_now(run.id) }
        .not_to change { gap_item.reload.attributes }
    end
  end
end
