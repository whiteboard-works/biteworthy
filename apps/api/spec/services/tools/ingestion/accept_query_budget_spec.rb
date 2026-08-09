require "rails_helper"

# Accepting a scan is the product's heaviest write and the one a user waits
# on. It used to cost a statement per payload row at three layers — a slug
# lookup, an insert, and a full rewrite of the denormalized array — so a
# 50-dish menu at 8 ingredients + 4 tags each ran ~2,700 statements. The
# budget below fences the shape, not the number: cost has to scale with
# dishes, not with associations, so re-introducing any per-row lookup,
# per-row insert or per-row array rewrite fails here rather than on a
# 200-dish menu in production.
RSpec.describe Tools::Ingestion::AcceptStagedItems, "query budget" do
  let(:owner)      { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, :staged, user: owner, restaurant: restaurant) }

  let(:ingredient_slugs) { INGREDIENT_SAMPLES.first(8).map { |s| s[:slug] } }
  let(:tag_slugs)        { TAG_SAMPLES.first(4).map { |s| s[:slug] } }

  dishes = 50
  # 10 statements per dish today; the headroom is for incidental additions,
  # not for another per-association layer.
  budget_per_dish = 12

  before do
    ingredient_slugs.each { |slug| create(:ingredient, slug: slug) }
    tag_slugs.each        { |slug| create(:tag, slug: slug) }

    dishes.times do |n|
      create(:ingestion_item,
             ingestion_run:       run,
             name:                "Dish #{n}",
             position:            n,
             ingredients_payload: ingredient_slugs.map { |s| { "slug" => s, "confidence" => 0.9, "source" => "match" } },
             tags_payload:        tag_slugs.map { |s| { "slug" => s, "confidence" => 0.9, "source" => "derived" } },
             prices_payload:      [{ "size" => nil, "price_cents" => 900 }])
    end
  end

  def count_queries
    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "accepts a #{dishes}-dish scan in a bounded number of queries" do
    queries = count_queries do
      described_class.call(scan_id: run.id, all: true, server_context: { user_id: owner.id })
    end

    expect(run.ingestion_items.where(decision: "accepted").count).to eq(dishes)
    expect(queries).to be < dishes * budget_per_dish
  end

  # The saving comes from writing the joins in bulk and rebuilding the
  # denormalized arrays once per dish. If those two ever fall out of step the
  # filter starts answering from an array that disagrees with the audit log —
  # a dish hidden or shown for the wrong reason — so assert them together.
  it "leaves every dish's denormalized arrays agreeing with its join rows" do
    described_class.call(scan_id: run.id, all: true, server_context: { user_id: owner.id })

    items = Item.where(restaurant: restaurant).includes(:item_ingredients, :item_tags).to_a
    expect(items.size).to eq(dishes)
    items.each do |item|
      expect(item.denormalized_ingredient_ids).to match_array(item.item_ingredients.map(&:ingredient_id))
      expect(item.denormalized_tag_ids).to        match_array(item.item_tags.map(&:tag_id))
      expect(item.item_ingredients.map(&:confidence).uniq).to eq(["suggested"])
      expect(item.item_ingredients.map(&:source).uniq).to     eq(["human"])
    end
  end
end
