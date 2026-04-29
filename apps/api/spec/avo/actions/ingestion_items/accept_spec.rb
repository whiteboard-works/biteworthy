require "rails_helper"

RSpec.describe Avo::Actions::IngestionItems::Accept do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, :staged, restaurant: restaurant) }

  let!(:beef)  { create(:ingredient, slug: "meat-beef") }
  let!(:vegan) { create(:tag, slug: "diet-vegan") }

  let(:item) do
    create(:ingestion_item, ingestion_run: run,
           ingredients_payload: [{ "slug" => "meat-beef", "confidence" => 0.97 }],
           tags_payload:        [{ "slug" => "diet-vegan", "confidence" => 0.10 }])
  end

  it "calls promote! and creates a real Item with confirmed sources" do
    described_class.accept_all([item])

    item.reload
    expect(item.decision).to     eq("accepted")
    expect(item.item).to         be_present
    expect(item.item.ingredients).to contain_exactly(beef)
    expect(item.item.tags).to        contain_exactly(vegan)
    expect(item.item.item_ingredients.first.source).to eq("human")
  end

  it "is idempotent — re-accepting an already-promoted item doesn't dup" do
    item.promote!
    original_item_id = item.reload.item.id

    expect {
      described_class.accept_all([item])
    }.not_to change(Item, :count)

    expect(item.reload.item.id).to eq(original_item_id)
  end

  it "calls maybe_publish! on the run after accepting" do
    # 5 items total: 4 already accepted, this Accept makes the 5th.
    # → 100% accepted → run flips to :published.
    4.times do |i|
      ai = create(:ingestion_item, ingestion_run: run, decision: "accepted")
      ai.update_column(:item_id, create(:item, restaurant: restaurant).id)
    end

    described_class.accept_all([item])

    expect(run.reload.published?).to be true
  end
end
