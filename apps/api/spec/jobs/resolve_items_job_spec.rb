require "rails_helper"

RSpec.describe ResolveItemsJob, type: :job do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run) { create(:ingestion_run, restaurant: restaurant, status: "resolving") }

  before do
    create(:ingredient, slug: "meat-beef")        # alias: steak
    create(:ingredient, slug: "herb-cilantro")
    create(:ingredient, slug: "fruit-lime")
  end

  def make_item(run, position:, name:, description: nil, decision: "pending")
    create(:ingestion_item,
           ingestion_run: run, position: position, name: name,
           description: description, decision: decision,
           ingredients_payload: [], tags_payload: [])
  end

  describe "a fully-matched run (no gaps)" do
    let!(:item) do
      make_item(run, position: 0, name: "Taco", description: "Grilled steak, cilantro, lime")
    end

    it "writes deterministic payloads, stages the run, and completes enrichment" do
      expect { described_class.perform_now(run.id) }.not_to have_enqueued_job(GapFillResolveJob)

      expect(run.reload.status).to eq("staged")
      expect(run.enrichment_status).to eq("completed")

      item.reload
      slugs = item.ingredients_payload.map { |r| r["slug"] }
      expect(slugs).to contain_exactly("meat-beef", "herb-cilantro", "fruit-lime")
      expect(item.ingredients_payload).to all(include("source" => "match"))
      expect(item.tags_payload.map { |r| r["slug"] }).to include("grilled")
    end
  end

  describe "a run with gap items" do
    let!(:matched)  { make_item(run, position: 0, name: "Limeade", description: "lime") }
    let!(:mystery)  { make_item(run, position: 1, name: "Caesar Salad") }

    it "stages immediately, leaves enrichment pending, and enqueues the gap-fill" do
      expect { described_class.perform_now(run.id) }
        .to have_enqueued_job(GapFillResolveJob).with(run.id)

      expect(run.reload.status).to eq("staged")
      expect(run.enrichment_status).to eq("pending")
      expect(mystery.reload.ingredients_payload).to eq([])
    end
  end

  describe "items accepted while the run was still resolving" do
    let!(:pre_accepted) do
      make_item(run, position: 0, name: "Taco", description: "steak, cilantro",
                     decision: "accepted")
    end

    it "promotes them with their fresh payloads" do
      expect { described_class.perform_now(run.id) }.to change(Item, :count).by(1)

      promoted = pre_accepted.reload.item
      expect(promoted).to be_present
      expect(promoted.ingredients.pluck(:slug)).to include("meat-beef", "herb-cilantro")
    end

    it "publishes the run when the accept threshold is already crossed" do
      described_class.perform_now(run.id)
      expect(run.reload.status).to eq("published")
    end

    it "a promotion failing mid-joins rolls back its partial Item (no false-safe live dish)" do
      make_item(run, position: 1, name: "Limeade", description: "lime", decision: "rejected")
      # The join insert raises AFTER Item.create! succeeded — the savepoint
      # in promote! must roll the partial Item back even though the job
      # rescues and carries on.
      allow(ItemIngredient).to receive(:insert_all).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(run.id)

      expect(Item.count).to eq(0)
      expect(pre_accepted.reload.item_id).to be_nil
      expect(run.reload.status).to eq("staged")
    end

    it "one failing promotion doesn't block staging" do
      # A rejected sibling keeps the accept ratio under the publish
      # threshold so the run should land at :staged despite the failure.
      make_item(run, position: 1, name: "Limeade", description: "lime", decision: "rejected")
      allow_any_instance_of(IngestionItem).to receive(:promote!).and_raise("boom")
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(run.id)

      expect(run.reload.status).to eq("staged")
      expect(Rails.logger).to have_received(:error).with(/promote of pre-accepted/)
    end
  end

  # Re-scan dedup — the resolve pass links staged items to the
  # restaurant's existing Items so the verify UI can stage updates
  # instead of duplicates (and PR3's apply path can merge on accept).
  describe "existing-item matching" do
    let!(:existing) { create(:item, restaurant: restaurant, name: "Taco", status: "published") }

    it "writes matched_item_id + match_score alongside the payloads" do
      row = make_item(run, position: 0, name: "Tacos", description: "steak")

      described_class.perform_now(run.id)

      row.reload
      expect(row.matched_item_id).to eq(existing.id)
      expect(row.match_score).to eq(1.0)
    end

    it "clears a stale match from a previous cycle when the item no longer matches" do
      row = make_item(run, position: 0, name: "Limeade", description: "lime")
      row.update!(matched_item_id: existing.id, match_score: 1.0)

      described_class.perform_now(run.id)

      expect(row.reload.matched_item_id).to be_nil
      expect(row.match_score).to be_nil
    end

    it "matches pre-accepted items before the batch promote, which applies the update" do
      row = make_item(run, position: 0, name: "Tacos", description: "steak",
                           decision: "accepted")

      expect { described_class.perform_now(run.id) }.not_to change(Item, :count)

      row.reload
      expect(row.matched_item_id).to eq(existing.id)
      # The accept recorded during :resolving promotes as an UPDATE at
      # :staged — dedup working end-to-end for the eager-accept flow.
      expect(row.item_id).to eq(existing.id)
      expect(existing.reload.description).to eq("steak")
    end
  end

  it "fails the run when there are no items" do
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq("failed")
    expect(run.failure_message).to eq("resolve: no_items")
  end

  it "is a no-op for staged/published/failed runs" do
    %w[staged published failed].each do |status|
      done = create(:ingestion_run, restaurant: restaurant, status: status)
      expect { described_class.perform_now(done.id) }
        .not_to change { done.reload.attributes }
    end
  end
end
