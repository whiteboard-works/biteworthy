require "rails_helper"
require Rails.root.join("db/migrate/20261013010000_move_hard_soda_aliases_to_beer")

# Production seeds only on first boot, so these aliases reach live through
# this migration. It and db/seeds/ingredients.yml have to agree.
RSpec.describe MoveHardSodaAliasesToBeer do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")) }

  before do
    create(:ingredient, slug: "alcohol", name: "Alcohol", path: "alcohol", aliases: described_class::MOVED)
    create(:ingredient, slug: "alcohol-beer", name: "Beer", path: "alcohol.beer", aliases: [])
    create(:ingredient, slug: "condiment-ginger-ale", name: "Ginger Ale", path: "condiment.ginger_ale",
                        aliases: [ "ginger beer" ])
    create(:ingredient, slug: "tree_nut-ginkgo", name: "Ginkgo", path: "tree_nut.ginkgo", aliases: [])
    create(:ingredient, slug: "tree_nut-hemp", name: "Hemp", path: "tree_nut.hemp", aliases: [])
    create(:ingredient, slug: "tree_nut-hickory", name: "Hickory", path: "tree_nut.hickory", aliases: [])
    create(:ingredient, slug: "tree_nut-mixed-nuts", name: "Mixed Nuts", path: "tree_nut.mixed_nuts",
                        aliases: [ "nuts" ])
  end

  it "leaves the database where the seed file is" do
    2.times { described_class.new.up }

    (described_class::ALIASES.keys + [ "alcohol" ]).each do |slug|
      expect(Ingredient.find_by!(slug: slug).aliases)
        .to match_array(seeded.find { |r| r["slug"] == slug }["aliases"])
    end
  end

  # The celiac presets avoid alcohol.beer, not the alcohol root.
  it "reads a hard soda as beer and a named nut as that nut" do
    described_class.new.up
    m = Ingestion::IngredientMatcher.new
    read = ->(text) { m.scan(text).first.map { |r| r[:slug] } }

    expect(read.("hard ginger beer")).to eq([ "alcohol-beer" ])
    expect(read.("ginger beer")).to eq([ "condiment-ginger-ale" ])
    expect(read.("hickory nuts")).to eq([ "tree_nut-hickory" ])
  end

  it "gives every single-word named nut a whole-phrase alias" do
    named = seeded.select { |r| r["path"].match?(/\Atree_nut\.[a-z]+\z/) && !r["name"].match?(/\s|nut/i) }

    named.each do |r|
      expect(Array(r["aliases"]).map(&:downcase)).to include("#{r['name'].downcase} nuts"), r["slug"]
    end
  end
end
