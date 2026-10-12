require "rails_helper"
require Rails.root.join("db/migrate/20261012233000_add_garlic_clove_alias")

RSpec.describe AddGarlicCloveAlias do
  before do
    create(:ingredient, slug: "vegetable-garlic", name: "Garlic", path: "vegetable.garlic", aliases: [])
    create(:ingredient, slug: "spice-clove", name: "Clove", path: "spice.clove", aliases: [])
  end

  it "makes garlic cloves resolve to garlic alone, and agrees with the seed file" do
    2.times { described_class.new.up }

    slugs = Ingestion::IngredientMatcher.new.scan("roasted garlic cloves, whole cloves").first.map { |m| m[:slug] }
    expect(slugs).to contain_exactly("vegetable-garlic", "spice-clove")
    seeded = YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")).find { |r| r["slug"] == "vegetable-garlic" }
    expect(seeded["aliases"]).to include("garlic clove")
    expect(Ingredient.find_by!(slug: "vegetable-garlic").aliases).to eq([ "garlic clove" ])
  end
end
