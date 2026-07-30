require "rails_helper"

# The TagDeriver / DeterministicResolver constants reference taxonomy
# slugs and ltree prefixes by string. This spec pins them against the
# production seed files so renaming or pruning a taxonomy node fails CI
# here instead of silently killing a derivation rule (dangerous for the
# allergen family).
RSpec.describe "deterministic-resolve taxonomy drift" do
  ingredient_seeds = YAML.load_file(Rails.root.join("db/seeds/ingredients.yml"))
  tag_seeds        = YAML.load_file(Rails.root.join("db/seeds/tags.yml"))

  ingredient_slugs = ingredient_seeds.map { |r| r["slug"] }.to_set
  ingredient_paths = ingredient_seeds.map { |r| r["path"] }
  tag_slugs        = tag_seeds.map { |r| r["slug"] }.to_set

  def prefix_exists?(paths, prefix)
    paths.any? { |p| p == prefix || p.start_with?("#{prefix}.") }
  end

  describe Ingestion::TagDeriver::Allergen do
    it "SUBTREE_TAGS keys are live ingredient path prefixes" do
      described_class::SUBTREE_TAGS.each_key do |prefix|
        expect(prefix_exists?(ingredient_paths, prefix))
          .to be(true), "no ingredient under path prefix #{prefix.inspect}"
      end
    end

    it "SUBTREE_TAGS values are live allergen tag slugs" do
      expect(described_class::SUBTREE_TAGS.values.to_set).to be_subset(tag_slugs)
    end

    it "SLUG_TAGS keys are live ingredient slugs" do
      described_class::SLUG_TAGS.each_key do |slug|
        expect(ingredient_slugs).to include(slug)
      end
    end

    it "SLUG_TAGS values are live tag slugs" do
      expect(described_class::SLUG_TAGS.values.flatten.to_set).to be_subset(tag_slugs)
    end

    it "covers every allergen-family tag with at least one derivation rule" do
      allergen_tags = tag_seeds.select { |r| r["family"] == "allergen" && r["path"].include?(".") }
                               .map { |r| r["slug"] }
      derivable = described_class::SUBTREE_TAGS.values + described_class::SLUG_TAGS.values.flatten
      expect(allergen_tags - derivable).to eq([]), "allergen tags with no rule: #{(allergen_tags - derivable).inspect}"
    end
  end

  {
    Ingestion::TagDeriver::Diet    => "diet",
    Ingestion::TagDeriver::Prep    => "prep",
    Ingestion::TagDeriver::Flavor  => "flavor",
    Ingestion::TagDeriver::Cuisine => "cuisine",
  }.each do |strategy, family|
    describe strategy do
      it "KEYWORDS keys are live #{family} tag slugs" do
        family_slugs = tag_seeds.select { |r| r["family"] == family }.map { |r| r["slug"] }.to_set
        expect(strategy::KEYWORDS.keys.to_set).to be_subset(family_slugs)
      end
    end
  end

  it "the resolver's condiment gap heuristic still points at a live prefix" do
    expect(prefix_exists?(ingredient_paths, "condiment")).to be(true)
  end
end
