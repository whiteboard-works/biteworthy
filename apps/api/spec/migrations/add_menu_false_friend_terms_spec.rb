require "rails_helper"
require Rails.root.join("db/migrate/20261013000000_add_menu_false_friend_terms")

# Production seeds only on first boot, so these terms reach live through
# this migration. It and db/seeds/ingredients.yml have to agree.
RSpec.describe AddMenuFalseFriendTerms do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")) }

  before do
    create(:ingredient, slug: "alcohol", name: "Alcohol", path: "alcohol", aliases: [])
    create(:ingredient, slug: "alcohol-beer", name: "Beer", path: "alcohol.beer", aliases: [])
    create(:ingredient, slug: "condiment-ginger-ale", name: "Ginger Ale", path: "condiment.ginger_ale", aliases: [])
    create(:ingredient, slug: "meat-beef", name: "Beef", path: "meat.beef", aliases: [])
    create(:ingredient, slug: "meat-beef-skirt-steak", name: "Skirt Steak", path: "meat.beef.skirt_steak",
                        aliases: [ "skirt" ])
    create(:ingredient, slug: "poultry-domestic-chicken", name: "Chicken", path: "poultry.chicken", aliases: [])
    create(:ingredient, slug: "tree_nut", name: "Tree Nut", path: "tree_nut", aliases: [])
    create(:ingredient, slug: "tree_nut-pine-nuts", name: "Pine nuts", path: "tree_nut.pine_nuts", aliases: [])
    create(:ingredient, slug: "tree_nut-almond", name: "Almond", path: "tree_nut.almond", aliases: [ "almonds" ])
    create(:ingredient, slug: "tree_nut-cashew", name: "Cashew", path: "tree_nut.cashew", aliases: [])
    create(:ingredient, slug: "tree_nut-hazel", name: "Hazel", path: "tree_nut.hazel", aliases: [ "hazelnut" ])
    create(:ingredient, slug: "tree_nut-walnut", name: "Walnut", path: "tree_nut.walnut", aliases: [])
    create(:ingredient, slug: "tree_nut-macadamia", name: "Macadamia", path: "tree_nut.macadamia", aliases: [])
    create(:ingredient, slug: "tree_nut-pecan", name: "Pecan", path: "tree_nut.pecan", aliases: [])
    create(:ingredient, slug: "tree_nut-pistacia", name: "Pistachio", path: "tree_nut.pistacia",
                        aliases: [ "Pistacia" ])
    create(:ingredient, slug: "legume-peanuts", name: "Peanuts", path: "legume.peanuts", aliases: [ "peanut" ])
    create(:ingredient, slug: "grain-wheat-breading", name: "Breading", path: "grain.wheat.breading", aliases: [])
  end

  it "adds the same nodes and aliases the seed file carries" do
    2.times { described_class.new.up }

    described_class::INGREDIENTS.each do |attrs|
      row  = Ingredient.find_by!(slug: attrs[:slug])
      seed = seeded.find { |r| r["slug"] == attrs[:slug] }
      expect([ row.name, row.path.to_s, row.aliases, row.allergen ])
        .to eq([ seed["name"], seed["path"], seed["aliases"], seed["allergen"] ])
    end
    described_class::ALIASES.each do |slug, aliases|
      # 20261013010000 moves the hard-soda aliases from the root to Beer.
      next if slug == "alcohol"

      expect(seeded.find { |r| r["slug"] == slug }["aliases"]).to include(*aliases)
      expect(Ingredient.find_by!(slug: slug).aliases).to include(*aliases)
    end
    expect(Ingredient.find_by!(slug: "meat-beef-skirt-steak").aliases).to eq(%w[skirt carne\ asada])
  end

  it "reads each menu phrase as what it is" do
    described_class.new.up
    m = Ingestion::IngredientMatcher.new
    read = ->(text) { m.scan(text).first.map { |r| r[:slug] } }

    expect(read.("fever tree ginger beer")).to eq([ "condiment-ginger-ale" ])
    expect(read.("hard ginger beer")).to eq([ "alcohol" ])
    expect(read.("campari glazed nuts")).to eq([ "tree_nut-mixed-nuts" ])
    expect(read.("pine nuts")).to eq([ "tree_nut-pine-nuts" ])
    expect(read.("carne asada steak")).to include("meat-beef-skirt-steak")
    expect(read.("chicken fried steak")).to eq([ "meat-beef-chicken-fried-steak" ])
    expect(read.("a&w root beer float")).to eq([ "condiment-root-beer" ])
    # A named nut is that nut, never also Mixed Nuts and the peanut it implies.
    %w[almond cashew hazel macadamia pecan pistachio walnut].each do |nut|
      expect(read.("#{nut} nuts")).not_to include("tree_nut-mixed-nuts")
    end
    expect(read.("nut-free brownie")).to be_empty
    # A kitchen offering a nut-free version still serves nuts by default.
    expect(read.("brownie with walnuts, nut free option available")).not_to be_empty
    expect(read.("may contain nuts")).to eq([ "tree_nut-mixed-nuts" ])
  end

  it "does nothing on a database the seed has not reached" do
    Ingredient.where(slug: "legume-peanuts").delete_all

    expect { described_class.new.up }.not_to change(Ingredient, :count)
  end
end
