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
end
