require "rails_helper"
require Rails.root.join("db/migrate/20261012230000_retire_false_friend_aliases")

# Production seeds only on first boot, so these alias changes reach live
# through this migration. It and db/seeds/ingredients.yml have to agree.
RSpec.describe RetireFalseFriendAliases do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")) }

  before do
    create(:ingredient, slug: "condiment-dressings-french", name: "French Dressing",
                        path: "condiment.dressings.french", aliases: %w[french catalina-ish])
    create(:ingredient, slug: "condiment-dressings-italian", name: "Italian Dressing",
                        path: "condiment.dressings.italian", aliases: %w[italian])
    create(:ingredient, slug: "vegetable-bell-pepper", name: "Bell pepper",
                        path: "vegetable.bell_pepper", aliases: [ "capsicum" ])
    create(:ingredient, slug: "herb-pepper", name: "Pepper", path: "herb.pepper", aliases: [])
  end

  it "removes only the named aliases, adds peppers, and agrees with the seed file" do
    2.times { described_class.new.up }

    expect(Ingredient.find_by!(slug: "condiment-dressings-french").aliases).to eq(%w[catalina-ish])
    expect(Ingredient.find_by!(slug: "condiment-dressings-italian").aliases).to eq([])
    expect(Ingredient.find_by!(slug: "vegetable-bell-pepper").aliases).to eq(%w[capsicum peppers])
    described_class::REMOVE.each do |slug, aliases|
      expect(seeded.find { |r| r["slug"] == slug }["aliases"]).not_to include(*aliases)
    end
    described_class::ADD.each do |slug, aliases|
      expect(seeded.find { |r| r["slug"] == slug }["aliases"]).to include(*aliases)
    end
  end

  it "stops matching French toast and Italian meatballs as dressing; peppers become bell pepper" do
    described_class.new.up

    slugs = Ingestion::IngredientMatcher.new
              .scan("French toast, Italian meatballs, roasted peppers, salt and pepper, italian dressing")
              .first.map { |m| m[:slug] }
    expect(slugs).to contain_exactly("vegetable-bell-pepper", "herb-pepper", "condiment-dressings-italian")
  end

  it "still retires the dressing aliases when another node is missing" do
    Ingredient.where(slug: "vegetable-bell-pepper").delete_all

    expect { described_class.new.up }.to output(/vegetable-bell-pepper not found/).to_stdout
    expect(Ingredient.find_by!(slug: "condiment-dressings-french").aliases).not_to include("french")
  end
end
