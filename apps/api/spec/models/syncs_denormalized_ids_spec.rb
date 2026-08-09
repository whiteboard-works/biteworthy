require "rails_helper"

# items.ingredient_ids / items.tag_ids are the GIN-indexed copy the dietary
# filter reads; the join rows are the source of truth. Deferring the sync is
# a performance move, so what matters here is that it cannot change the
# answer — including when the write it was batching blows up halfway.
RSpec.describe SyncsDenormalizedIds do
  let(:item)  { create(:item) }
  let!(:beef) { create(:ingredient, slug: "meat-beef") }
  let!(:rice) { create(:ingredient, slug: "grain-rice") }
  let!(:tag)  { create(:tag, slug: "cuisine-mexican") }

  def array_writes
    writes = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      writes += 1 if payload[:sql].match?(/UPDATE "items" SET "(ingredient|tag)_ids"/)
    end
    yield
    writes
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "rewrites the array once per join outside a deferral" do
    writes = array_writes do
      [beef, rice].each { |i| ItemIngredient.create!(item: item, ingredient: i, confidence: "confirmed", source: "human") }
    end

    expect(writes).to eq(2)
    expect(item.reload.denormalized_ingredient_ids).to match_array([beef.id, rice.id])
  end

  it "rewrites each touched array once for the whole block" do
    writes = array_writes do
      Item.defer_denormalization do
        [beef, rice].each { |i| ItemIngredient.create!(item: item, ingredient: i, confidence: "confirmed", source: "human") }
        ItemTag.create!(item: item, tag: tag, confidence: "confirmed", source: "human")
      end
    end

    expect(writes).to eq(2) # one for ingredient_ids, one for tag_ids
    expect(item.reload.denormalized_ingredient_ids).to match_array([beef.id, rice.id])
    expect(item.denormalized_tag_ids).to eq([tag.id])
  end

  it "keeps the array honest when a deferred block raises partway through" do
    ItemIngredient.create!(item: item, ingredient: beef, confidence: "confirmed", source: "human")

    expect {
      Item.defer_denormalization do
        ItemIngredient.create!(item: item, ingredient: rice, confidence: "confirmed", source: "human")
        raise "boom"
      end
    }.to raise_error("boom")

    # The join row rolled back with the block, so the array must still
    # describe exactly the joins that survived.
    expect(item.reload.item_ingredients.map(&:ingredient_id)).to eq([beef.id])
    expect(item.denormalized_ingredient_ids).to eq([beef.id])
  end

  it "follows a destroy inside a deferral too" do
    joins = [beef, rice].map { |i| ItemIngredient.create!(item: item, ingredient: i, confidence: "confirmed", source: "human") }

    Item.defer_denormalization { joins.first.destroy }

    expect(item.reload.denormalized_ingredient_ids).to eq([rice.id])
  end
end
