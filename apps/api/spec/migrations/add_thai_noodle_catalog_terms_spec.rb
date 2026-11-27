require "rails_helper"
require Rails.root.join("db/migrate/20261127220000_add_thai_noodle_catalog_terms")

# Production seeds only on first boot, so these terms reach live through
# this migration. It and db/seeds/ingredients.yml have to agree.
RSpec.describe AddThaiNoodleCatalogTerms do
  let(:seeded) { YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")) }

  around do |example|
    was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was
  end

  before do
    create(:ingredient, slug: "grain-rice-noodle", name: "Rice Noodle",
                        path: "grain.rice.noodle", aliases: %w[rice\ stick ho\ fun])
    create(:ingredient, slug: "grain-wheat-noodle-egg", name: "Egg Noodle",
                        path: "grain.wheat.noodle.egg", aliases: [])
    create(:ingredient, slug: "grain-wheat-wonton", name: "Wonton",
                        path: "grain.wheat.wonton", aliases: [ "wonton wrapper" ])
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
      expect(seeded.find { |r| r["slug"] == slug }["aliases"]).to include(*aliases)
      expect(Ingredient.find_by!(slug: slug).aliases).to include(*aliases)
    end
  end

  it "does nothing on a database the seed has not reached" do
    Ingredient.where(slug: "grain-rice-noodle").delete_all

    expect { described_class.new.up }.not_to change(Ingredient, :count)
  end
end
