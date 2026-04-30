require "rails_helper"

# Phase 3.1 — production seeds for the 10 curated dietary profiles
# the onboarding flow (Phase 3.2) shows as preset chips. Verifies
# the YAML loads, the path-prefix join queries resolve correctly,
# and the most-relied-on presets (Vegan, Celiac, Halal) cover the
# right subtrees.

RSpec.describe "dietary profiles seed", type: :model do
  let(:yaml_path) { Rails.root.join("db/seeds/dietary_profiles.yml") }
  let(:rows)      { YAML.load_file(yaml_path) }

  # Re-implement the seeds.rb body in the spec — the helpers there
  # aren't exposed as a class. Mirrors the production loader exactly.
  def run_seeds!
    rows.each do |row|
      row = row.deep_dup
      ingredient_slugs = row.delete("avoid_ingredient_slugs") || []
      ingredient_paths = row.delete("avoid_ingredient_paths") || []
      tag_slugs        = row.delete("avoid_tag_slugs")        || []
      tag_paths        = row.delete("avoid_tag_paths")        || []

      profile = DietaryProfile.find_or_initialize_by(slug: row["slug"])
      profile.assign_attributes(row)
      profile.save!

      ingredient_ids = (
        Ingredient.where(slug: ingredient_slugs).pluck(:id) +
        (ingredient_paths.any? ? Ingredient.where("path <@ ARRAY[?]::ltree[]", ingredient_paths).pluck(:id) : [])
      ).uniq

      tag_ids = (
        Tag.where(slug: tag_slugs).pluck(:id) +
        (tag_paths.any? ? Tag.where("path <@ ARRAY[?]::ltree[]", tag_paths).pluck(:id) : [])
      ).uniq

      Ingredient.where(id: ingredient_ids).find_each do |ing|
        DietaryProfileIngredient.find_or_create_by!(
          dietary_profile: profile, ingredient: ing, rule: "avoid"
        )
      end

      Tag.where(id: tag_ids).find_each do |tag|
        DietaryProfileTag.find_or_create_by!(
          dietary_profile: profile, tag: tag, rule: "avoid"
        )
      end
    end
  end

  describe "the YAML catalog" do
    it "ships exactly the 10 presets the onboarding flow shows" do
      slugs = rows.map { |r| r["slug"] }
      expect(slugs).to contain_exactly(
        "vegan", "vegetarian", "pescatarian",
        "celiac", "gluten-free", "dairy-free",
        "halal", "kosher",
        "tree-nut-allergy", "peanut-allergy"
      )
    end

    it "every preset has a name + description (used by onboarding cards)" do
      rows.each do |r|
        expect(r["name"]).to be_present, "missing name on #{r['slug']}"
        expect(r["description"]).to be_present, "missing description on #{r['slug']}"
        expect(r["description"].length).to be < 200, "#{r['slug']} description too long for a card"
      end
    end
  end

  describe "loading + idempotence" do
    before do
      # Need the ingredient catalog so the path-prefix joins return
      # something — we pre-load the same YAML the production seed
      # uses, scoped to the few entries the assertions check.
      seed_ingredients(%w[
        dairy dairy-cheese dairy-butter
        egg egg-chicken-egg
        meat meat-beef-cattle meat-swine-domestic-pig
        poultry poultry-domestic-chicken
        fish fish-salmon
        shellfish shellfish-crustacean-shrimp
        grain grain-wheat grain-rye grain-barley grain-rice
        legume legume-peanuts
        tree_nut tree_nut-almond
        alcohol alcohol-red-wine
      ])
    end

    it "loads all 10 presets" do
      expect { run_seeds! }.to change(DietaryProfile, :count).by(10)
    end

    it "is idempotent — re-running doesn't duplicate join rows" do
      run_seeds!
      first_join_count = DietaryProfileIngredient.count

      run_seeds!

      expect(DietaryProfile.count).to eq(10)
      expect(DietaryProfileIngredient.count).to eq(first_join_count)
    end
  end

  describe "Vegan preset (canary for path-prefix expansion)" do
    before do
      seed_ingredients(%w[
        dairy dairy-cheddar dairy-butter
        egg egg-chicken-egg
        meat meat-beef-cattle
        poultry poultry-domestic-chicken
        fish fish-salmon
        shellfish shellfish-crustacean-shrimp
        vegetable vegetable-onion
        grain grain-rice
      ])
      run_seeds!
    end

    let(:vegan) { DietaryProfile.find_by!(slug: "vegan") }

    it "avoids every ingredient under dairy / egg / meat / poultry / fish / shellfish" do
      avoid_paths = vegan.ingredients.map(&:path).map(&:to_s)
      expect(avoid_paths).to include("dairy", "dairy.cheddar", "dairy.butter")
      expect(avoid_paths).to include("egg", "egg.chicken_egg")
      expect(avoid_paths).to include("meat", "meat.beef.cattle")
      expect(avoid_paths).to include("poultry", "poultry.domestic.chicken")
      expect(avoid_paths).to include("fish", "fish.salmon")
      expect(avoid_paths).to include("shellfish", "shellfish.crustacean.shrimp")
    end

    it "does NOT avoid plant ingredients (vegetable / grain)" do
      avoid_paths = vegan.ingredients.map(&:path).map(&:to_s)
      expect(avoid_paths).not_to include("vegetable.onion")
      expect(avoid_paths).not_to include("grain.rice")
    end
  end

  describe "Celiac preset (canary for surgical-leaf selection)" do
    before do
      seed_ingredients(%w[grain grain-wheat grain-rye grain-barley grain-rice grain-corn])
      run_seeds!
    end

    let(:celiac) { DietaryProfile.find_by!(slug: "celiac") }

    it "avoids gluten-bearing grains specifically" do
      avoid_paths = celiac.ingredients.map(&:path).map(&:to_s)
      expect(avoid_paths).to contain_exactly("grain.wheat", "grain.rye", "grain.barley")
    end

    it "does NOT avoid gluten-free grains (rice, corn)" do
      avoid_paths = celiac.ingredients.map(&:path).map(&:to_s)
      expect(avoid_paths).not_to include("grain.rice", "grain.maize_corn")
    end
  end

  describe "Halal preset (canary for path + alcohol)" do
    before do
      seed_ingredients(%w[meat-swine-domestic-pig alcohol alcohol-red-wine meat-beef-cattle])
      run_seeds!
    end

    it "avoids pork (meat.swine subtree) and alcohol" do
      halal = DietaryProfile.find_by!(slug: "halal")
      avoid_paths = halal.ingredients.map(&:path).map(&:to_s)
      expect(avoid_paths).to include("meat.swine.domestic_pig")
      expect(avoid_paths).to include("alcohol", "alcohol.red_wine")
      expect(avoid_paths).not_to include("meat.beef.cattle")
    end
  end

  # Helper: pull a known subset of ingredients from the production
  # YAML so the seed expansion has something to match.
  def seed_ingredients(slugs)
    catalog = YAML.load_file(Rails.root.join("db/seeds/ingredients.yml"))
    catalog.select { |r| slugs.include?(r["slug"]) }.each do |row|
      ing = Ingredient.find_or_initialize_by(slug: row["slug"])
      ing.assign_attributes(row)
      ing.save!
    end
  end
end
