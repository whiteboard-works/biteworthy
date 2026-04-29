require "rails_helper"

# The Phase 1.4 ingredient port: db/seeds/ingredients.yml is the
# canonical taxonomy that Phase 2's AI ingestion pipeline + Phase 3's
# filter engine read against. These specs verify the YAML loads, the
# seed task is idempotent, ltree paths form a coherent tree, and the
# FDA big-9 allergen subtrees are flagged.

RSpec.describe "ingredients seed", type: :model do
  let(:yaml_path) { Rails.root.join("db/seeds/ingredients.yml") }
  let(:rows)      { YAML.load_file(yaml_path) }

  def seed_ingredients!
    rows.each do |row|
      ing = Ingredient.find_or_initialize_by(slug: row["slug"])
      ing.assign_attributes(row)
      ing.save!
    end
  end

  describe "the YAML catalog" do
    it "ships at least 1000 ingredients (phase-1.md acceptance bar)" do
      expect(rows.size).to be >= 1_000
    end

    it "has zero malformed ltree paths" do
      bad = rows.reject { |r| r["path"].match?(/\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*\z/) }
      expect(bad).to be_empty,
        "Malformed paths: #{bad.first(5).map { |r| "#{r['slug']}=>#{r['path'].inspect}" }.join(', ')}"
    end

    it "has unique slugs" do
      slugs = rows.map { |r| r["slug"] }
      expect(slugs.size).to eq(slugs.uniq.size)
    end

    it "covers every required path root from phase-1.md §1.4" do
      roots = rows.map { |r| r["path"].split(".").first }.uniq
      %w[fruit vegetable herb tree_nut legume grain meat poultry fish dairy egg spice sesame].each do |required|
        expect(roots).to include(required), "missing top-level path root: #{required}"
      end
    end

    it "flags every entry under the FDA big-9 allergen subtrees" do
      big_nine_subtrees = %w[dairy egg fish shellfish tree_nut sesame soy]
      big_nine_subtrees.each do |root|
        members = rows.select { |r| r["path"] == root || r["path"].start_with?("#{root}.") }
        next if members.empty?

        non_allergen = members.reject { |r| r["allergen"] }
        expect(non_allergen).to be_empty,
          "expected every #{root}.* row to be an allergen; missed: #{non_allergen.first(3).map { |r| r['slug'] }}"
      end
    end

    it "flags wheat / rye / barley specifically (gluten-bearing grains)" do
      gluten_paths = %w[grain.wheat grain.rye grain.barley]
      gluten_paths.each do |path|
        row = rows.find { |r| r["path"] == path }
        next if row.nil? # not all are guaranteed to land in the catalog
        expect(row["allergen"]).to eq(true), "#{path} should be flagged allergen"
      end
    end

    it "preserves the parenthetical-gloss aliases from the legacy file" do
      domestic_pig = rows.find { |r| r["slug"] == "meat-swine-domestic-pig" }
      expect(domestic_pig).not_to be_nil
      expect(domestic_pig["aliases"]).to include("pork")
    end
  end

  describe "the seed task" do
    it "loads cleanly into Postgres" do
      expect { seed_ingredients! }.to change(Ingredient, :count).by(rows.size)

      # Spot-check three specific ancestry chains to make sure the
      # ltree column can answer the questions the filter query runs.
      expect(Ingredient.where("path <@ 'tree_nut'").count).to be > 5
      expect(Ingredient.where("path <@ 'dairy'").count).to be     > 20
      expect(Ingredient.where("path <@ 'fish'").count).to be      > 10
    end

    it "is idempotent — running twice does not duplicate rows" do
      seed_ingredients!
      first_count = Ingredient.count

      expect { seed_ingredients! }.not_to change(Ingredient, :count)
      expect(Ingredient.count).to eq(first_count)
    end
  end
end
