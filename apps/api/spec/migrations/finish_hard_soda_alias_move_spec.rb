require "rails_helper"
require Rails.root.join("db/migrate/20261013010000_move_hard_soda_aliases_to_beer")
require Rails.root.join("db/migrate/20261125220000_finish_hard_soda_alias_move")

# Codex on #925: 20261013010000 no-ops entirely when an optional named-nut
# node is missing. This follow-up requires only alcohol + alcohol.beer
# and skips missing nut nodes one by one.
RSpec.describe FinishHardSodaAliasMove do
  around do |example|
    was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was
  end

  before do
    create(:ingredient, slug: "alcohol", name: "Alcohol", path: "alcohol",
                        aliases: MoveHardSodaAliasesToBeer::MOVED)
    create(:ingredient, slug: "alcohol-beer", name: "Beer", path: "alcohol.beer", aliases: [])
    create(:ingredient, slug: "condiment-ginger-ale", name: "Ginger Ale", path: "condiment.ginger_ale",
                        aliases: [ "ginger beer" ])
    create(:ingredient, slug: "tree_nut-hemp", name: "Hemp", path: "tree_nut.hemp", aliases: [])
    create(:ingredient, slug: "tree_nut-hickory", name: "Hickory", path: "tree_nut.hickory", aliases: [])
    create(:ingredient, slug: "tree_nut-mixed-nuts", name: "Mixed Nuts", path: "tree_nut.mixed_nuts",
                        aliases: [ "nuts" ])
  end

  it "keeps the moved-alias list in lockstep with the catalog migration" do
    expect(described_class::MOVED).to eq(MoveHardSodaAliasesToBeer::MOVED)
  end

  it "moves hard-soda aliases when a named-nut node is missing" do
    described_class.new.up
    m = Ingestion::IngredientMatcher.new
    read = ->(text) { m.scan(text).first.map { |r| r[:slug] } }

    expect(Ingredient.find_by!(slug: "alcohol").aliases).not_to include("hard ginger beer")
    expect(Ingredient.find_by!(slug: "alcohol-beer").aliases).to include("hard ginger beer")
    expect(read.("hard ginger beer")).to eq([ "alcohol-beer" ])
    expect(read.("ginger beer")).to eq([ "condiment-ginger-ale" ])
    expect(Ingredient.find_by!(slug: "tree_nut-hemp").aliases).to include("hemp nuts")
    expect(Ingredient.find_by!(slug: "tree_nut-hickory").aliases).to include("hickory nuts")
    expect(Ingredient.find_by(slug: "tree_nut-ginkgo")).to be_nil
  end

  it "still moves hard sodas when every named-nut node is missing" do
    Ingredient.find_by!(slug: "tree_nut-hemp").destroy!
    Ingredient.find_by!(slug: "tree_nut-hickory").destroy!

    described_class.new.up

    expect(Ingredient.find_by!(slug: "alcohol").aliases).not_to include(*described_class::MOVED)
    expect(Ingredient.find_by!(slug: "alcohol-beer").aliases).to include(*described_class::MOVED)
  end

  it "skips a missing nut node without blocking the others" do
    create(:ingredient, slug: "tree_nut-ginkgo", name: "Ginkgo", path: "tree_nut.ginkgo", aliases: [])
    Ingredient.find_by!(slug: "tree_nut-hemp").destroy!

    described_class.new.up

    expect(Ingredient.find_by!(slug: "tree_nut-ginkgo").aliases).to include("ginkgo nuts")
    expect(Ingredient.find_by(slug: "tree_nut-hemp")).to be_nil
    expect(Ingredient.find_by!(slug: "tree_nut-hickory").aliases).to include("hickory nuts")
  end

  it "is a no-op on a second run" do
    2.times { described_class.new.up }

    expect(Ingredient.find_by!(slug: "alcohol").aliases).not_to include("hard ginger beer")
    expect(Ingredient.find_by!(slug: "alcohol-beer").aliases).to match_array(described_class::MOVED)
  end

  it "does not run when the alcohol nodes are missing" do
    Ingredient.find_by!(slug: "alcohol-beer").destroy!

    described_class.new.up

    expect(Ingredient.find_by!(slug: "alcohol").aliases).to include("hard ginger beer")
  end
end
