require "rails_helper"
require Rails.root.join("db/migrate/20261012210000_add_cheese_catalog_terms")

# Production seeds only on first boot, so these terms reach live through
# this migration. It and db/seeds/ingredients.yml have to agree.
RSpec.describe AddCheeseCatalogTerms do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")) }

  def seed_row(slug) = seeded.find { |r| r["slug"] == slug }

  before { create(:ingredient, slug: "dairy", name: "Dairy", path: "dairy", aliases: [ "lacto" ]) }

  it "adds the same nodes and aliases the seed file carries" do
    described_class.new.up

    described_class::INGREDIENTS.each do |attrs|
      row = Ingredient.find_by!(slug: attrs[:slug])
      seed = seed_row(attrs[:slug])
      expect(seed).to be_present, "#{attrs[:slug]} is not in ingredients.yml"
      expect([ row.name, row.path.to_s, row.aliases, row.allergen ])
        .to eq([ seed["name"], seed["path"], seed["aliases"], seed["allergen"] ])
    end
    described_class::ALIASES.each do |slug, aliases|
      expect(seed_row(slug)["aliases"]).to include(*aliases)
    end
  end

  it "merges aliases with what production already has instead of replacing them" do
    2.times { described_class.new.up }

    expect(Ingredient.find_by!(slug: "dairy").aliases).to eq(%w[lacto cheese])
    expect(Ingredient.where(slug: "dairy-grana-padano").count).to eq(1)
  end

  it "resolves bare cheese to dairy, leaving goat cheese on its node and cheesecake alone" do
    described_class.new.up
    create(:ingredient, slug: "dairy-goat-cheese", name: "Goat Cheese", path: "dairy.goat_cheese", aliases: [])

    matches, = Ingestion::IngredientMatcher.new.scan("goat cheese, melted cheese, grana padano, cheesecake")
    expect(matches.map { |m| m[:slug] }).to contain_exactly("dairy-goat-cheese", "dairy", "dairy-grana-padano")
  end

  # An admin may have placed one of these elsewhere through the taxonomy
  # tools; failing here would block every API deploy.
  it "leaves a node an admin placed elsewhere, without failing the migration" do
    create(:ingredient, slug: "dairy-scamorza", name: "Scamorza", path: "dairy.smoked_scamorza", aliases: [])

    expect { described_class.new.up }.to output(/dairy-scamorza exists at dairy.smoked_scamorza/).to_stdout
    expect(Ingredient.find_by!(slug: "dairy-scamorza").path.to_s).to eq("dairy.smoked_scamorza")
    expect(Ingredient.where(slug: "dairy-grana-padano")).to exist
  end

  it "does nothing under an unseeded taxonomy rather than create orphans" do
    Ingredient.where(slug: "dairy").delete_all

    expect { described_class.new.up }.to output(/not seeded/).to_stdout
    expect(Ingredient.where(slug: "dairy-grana-padano")).not_to exist
  end
end
