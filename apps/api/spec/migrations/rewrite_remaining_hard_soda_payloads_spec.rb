require "rails_helper"
require Rails.root.join("db/migrate/20261013010000_move_hard_soda_aliases_to_beer")
require Rails.root.join("db/migrate/20261013020000_rewrite_hard_soda_item_ingredients_to_beer")
require Rails.root.join("db/migrate/20261125220100_rewrite_remaining_hard_soda_payloads")

# Codex on #925: 20261013020000 rewrote pending/edited payloads only.
# Accepted/rejected rows kept `alcohol`, and undo_staged_item returns
# them to pending so re-accept via promote! would recreate the root join.
RSpec.describe RewriteRemainingHardSodaPayloads do
  let!(:alcohol) do
    create(:ingredient, slug: "alcohol", name: "Alcohol", path: "alcohol",
                        aliases: MoveHardSodaAliasesToBeer::MOVED)
  end
  let!(:beer) do
    create(:ingredient, slug: "alcohol-beer", name: "Beer", path: "alcohol.beer", aliases: [])
  end
  let!(:celiac) { create(:dietary_profile, slug: "celiac") }
  let(:restaurant) { create(:restaurant) }

  around do |example|
    was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was
  end

  before { celiac.dietary_profile_ingredients.create!(ingredient: beer, rule: "avoid") }

  def celiac_reasons(item)
    item = item.reload
    filter = Menus::Filter.build(preset_slug: "celiac")
    filter.reasons_for(item, Menus::Labels.for_filter([ item ], filter))
  end

  def alcohol_payload
    [ { "slug" => "alcohol", "confidence" => 0.95, "source" => "match" } ]
  end

  it "keeps the moved-alias list in lockstep with the catalog migration" do
    expect(described_class::MOVED).to eq(MoveHardSodaAliasesToBeer::MOVED)
  end

  it "rewrites an accepted payload after 20261013020000 so undo then promote lands on beer" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "Hard Ginger Beer",
                                     description: "", ingredients_payload: alcohol_payload)
    staged.promote!

    RewriteHardSodaItemIngredientsToBeer.new.up
    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol" ])

    described_class.new.up
    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol-beer" ])

    staged.undo!
    promoted = staged.reload.promote!

    expect(promoted.item_ingredients.map(&:ingredient_id)).to eq([ beer.id ])
    expect(celiac_reasons(promoted)).not_to be_empty
  end

  it "rewrites a rejected payload so a later promote lands on beer" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "Spiked Root Beer",
                                     decision: "rejected", description: "",
                                     ingredients_payload: alcohol_payload)

    RewriteHardSodaItemIngredientsToBeer.new.up
    described_class.new.up

    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol-beer" ])

    staged.update!(decision: "pending")
    promoted = staged.reload.promote!

    expect(promoted.item_ingredients.map(&:ingredient_id)).to eq([ beer.id ])
    expect(celiac_reasons(promoted)).not_to be_empty
  end

  it "does not rewrite a wine payload that is not a hard soda" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "House Cabernet",
                                     decision: "accepted", description: "",
                                     ingredients_payload: alcohol_payload)

    described_class.new.up

    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol" ])
  end

  it "is a no-op on a second run" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "Hard Root Beer",
                                     decision: "rejected", description: "",
                                     ingredients_payload: alcohol_payload)

    2.times { described_class.new.up }

    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol-beer" ])
  end
end
