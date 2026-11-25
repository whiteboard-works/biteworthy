require "rails_helper"
require Rails.root.join("db/migrate/20261013010000_move_hard_soda_aliases_to_beer")
require Rails.root.join("db/migrate/20261013020000_rewrite_hard_soda_item_ingredients_to_beer")

# Codex on #925: moving the aliases only changes future matcher runs.
# A dish already joined to the alcohol root stays visible to a celiac
# preset that avoids alcohol.beer. This migration is the live-row half.
RSpec.describe RewriteHardSodaItemIngredientsToBeer do
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

  def join_for(item, ingredient, source: "match")
    ItemIngredient.create!(item: item, ingredient: ingredient,
                           confidence: "suggested", source: source)
  end

  def hard_soda(name: "Hard Ginger Beer", description: "", source: "match")
    item = create(:item, restaurant: restaurant, name: name, description: description)
    [ item, join_for(item, alcohol, source: source) ]
  end

  def celiac_reasons(item)
    item = item.reload
    filter = Menus::Filter.build(preset_slug: "celiac")
    filter.reasons_for(item, Menus::Labels.for_filter([ item ], filter))
  end

  it "keeps the moved-alias list in lockstep with the catalog migration" do
    expect(described_class::MOVED).to eq(MoveHardSodaAliasesToBeer::MOVED)
  end

  # The finding: after the alias move as originally shipped, an existing
  # join still points at alcohol, so the celiac preset does not hide it.
  it "is a real gap on the alias-only migration: the live join stays on alcohol" do
    item, join = hard_soda
    # The catalog migration also writes named-nut aliases; those nodes
    # have to exist or `up` no-ops and this example would pass for the
    # wrong reason.
    %w[tree_nut-ginkgo tree_nut-hemp tree_nut-hickory].each do |slug|
      create(:ingredient, slug: slug, name: slug, path: slug.tr("-", "."), aliases: [])
    end

    MoveHardSodaAliasesToBeer.new.up

    expect(Ingredient.find_by!(slug: "alcohol-beer").aliases).to include("hard ginger beer")
    expect(join.reload.ingredient_id).to eq(alcohol.id)
    expect(item.reload.denormalized_ingredient_ids).to eq([ alcohol.id ])
    expect(celiac_reasons(item)).to be_empty
  end

  it "rewrites an existing matcher join onto beer and hides the dish from celiac" do
    item, join = hard_soda

    expect(celiac_reasons(item)).to be_empty

    described_class.new.up

    expect(join.reload.ingredient_id).to eq(beer.id)
    expect(item.reload.denormalized_ingredient_ids).to eq([ beer.id ])
    expect(celiac_reasons(item)).not_to be_empty
  end

  it "is a no-op on a second run" do
    _item, join = hard_soda

    2.times { described_class.new.up }

    expect(join.reload.ingredient_id).to eq(beer.id)
    expect(ItemIngredient.where(id: join.id).count).to eq(1)
  end

  it "drops the alcohol-root join when the dish already has a beer join" do
    item, alcohol_join = hard_soda(name: "Hard Root Beer")
    beer_join = join_for(item, beer)

    described_class.new.up

    expect(ItemIngredient.exists?(alcohol_join.id)).to be(false)
    expect(beer_join.reload.ingredient_id).to eq(beer.id)
    expect(item.reload.denormalized_ingredient_ids).to eq([ beer.id ])
  end

  it "rewrites a curator row when the dish name is the moved alias" do
    _item, join = hard_soda(name: "Spiked Root Beer", source: "human")

    described_class.new.up

    expect(join.reload.ingredient_id).to eq(beer.id)
  end

  it "leaves a curator alcohol join alone when only the description mentions a hard soda" do
    item = create(:item, restaurant: restaurant, name: "House Cabernet",
                         description: "Pair with our hard ginger beer")
    join = join_for(item, alcohol, source: "human")

    described_class.new.up

    expect(join.reload.ingredient_id).to eq(alcohol.id)
  end

  it "does not rewrite an alcohol join on a dish that never matched the aliases" do
    item = create(:item, restaurant: restaurant, name: "House Cabernet")
    join = join_for(item, alcohol, source: "match")

    described_class.new.up

    expect(join.reload.ingredient_id).to eq(alcohol.id)
    expect(item.reload.denormalized_ingredient_ids).to eq([ alcohol.id ])
  end

  # The matcher folds hyphens, slashes, and extra spaces before lookup.
  # Lowercasing the raw stored name misses those spellings, so a join
  # the matcher wrote to alcohol would stay there.
  it "rewrites joins whose stored spelling only matches after MenuText.normalize" do
    hyphen, hyphen_join = hard_soda(name: "Hard-Ginger Beer")
    slash, slash_join = hard_soda(name: "Hard / Root Beer")
    spaces, spaces_join = hard_soda(name: "Spiked  Root  Beer")

    described_class.new.up

    expect(hyphen_join.reload.ingredient_id).to eq(beer.id)
    expect(slash_join.reload.ingredient_id).to eq(beer.id)
    expect(spaces_join.reload.ingredient_id).to eq(beer.id)
    expect(celiac_reasons(hyphen)).not_to be_empty
    expect(celiac_reasons(slash)).not_to be_empty
    expect(celiac_reasons(spaces)).not_to be_empty
  end

  # Pending/edited staged rows have no ItemIngredient yet. promote! writes
  # whatever slug is still in ingredients_payload, so leaving alcohol there
  # recreates the gap on accept.
  it "rewrites a pending hard-soda payload so promote! lands on beer" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "Hard Ginger Beer",
                                     description: "",
                                     ingredients_payload: [
                                       { "slug" => "alcohol", "confidence" => 0.95, "source" => "match" }
                                     ])

    described_class.new.up
    promoted = staged.reload.promote!

    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol-beer" ])
    expect(promoted.item_ingredients.map(&:ingredient_id)).to eq([ beer.id ])
    expect(celiac_reasons(promoted)).not_to be_empty
  end

  it "does not rewrite a pending wine payload that is not a hard soda" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    staged = create(:ingestion_item, ingestion_run: run, name: "House Cabernet",
                                     description: "",
                                     ingredients_payload: [
                                       { "slug" => "alcohol", "confidence" => 0.95, "source" => "match" }
                                     ])

    described_class.new.up

    expect(staged.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol" ])
  end

  # Codex on #925 (comment 4700839319): STAGED is pending/edited only.
  # promote! sets decision=accepted and leaves the payload as scanned.
  # undo then re-accept would recreate the alcohol-root join. The
  # follow-up migration (20261125220100) rewrites every decision.
  it "leaves accepted and rejected payloads on alcohol" do
    run = create(:ingestion_run, :staged, restaurant: restaurant)
    payload = [ { "slug" => "alcohol", "confidence" => 0.95, "source" => "match" } ]
    accepted = create(:ingestion_item, ingestion_run: run, name: "Hard Ginger Beer",
                                       description: "", ingredients_payload: payload)
    accepted.promote!
    rejected = create(:ingestion_item, ingestion_run: run, name: "Spiked Root Beer",
                                       decision: "rejected", description: "",
                                       ingredients_payload: payload)

    described_class.new.up

    expect(accepted.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol" ])
    expect(rejected.reload.ingredients_payload.map { |r| r["slug"] }).to eq([ "alcohol" ])
  end
end
