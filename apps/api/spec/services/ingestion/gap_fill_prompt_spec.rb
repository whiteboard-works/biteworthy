require "rails_helper"

RSpec.describe Ingestion::GapFillPrompt do
  describe ".items_block" do
    it "renders name/section/description plus the matched + unmatched context lines" do
      block = described_class.items_block([
        { name: "Caesar Salad", section: "Salads", description: "with dressing",
          matched: %w[dairy-parmesan], unmatched: ["caesar dressing"] },
        { name: "Mystery Bowl", section: nil, description: nil, matched: [], unmatched: [] },
      ])

      expect(block).to eq(<<~TXT.strip)
        [0] Caesar Salad (section: Salads)
            description: with dressing
            matched: dairy-parmesan
            unmatched: caesar dressing
        [1] Mystery Bowl
      TXT
    end
  end

  describe ".system" do
    before do
      create(:tag, slug: "italian", name: "Italian", family: "cuisine", path: "cuisine.italian")
      create(:tag, slug: "fried", name: "Fried", family: "prep", path: "prep.fried")
      create(:ingredient, slug: "meat-beef")
    end

    it "carries instructions and the ingredient catalog with one trailing cache breakpoint, and no tag catalog" do
      client = AnthropicClient.new
      blocks = described_class.system(client)

      expect(blocks.length).to eq(2)
      expect(blocks[0][:text]).to eq(described_class::SYSTEM_INSTRUCTIONS)
      expect(blocks[1][:text]).to include("meat-beef")

      # No tag family is shipped: allergen/diet/prep/flavor are derived
      # in code and cuisine is Jev's, so none may tempt the model.
      expect(blocks.map { |b| b[:text] }.join).not_to include("italian", "fried")

      expect(blocks[0]).not_to have_key(:cache_control)
      expect(blocks[1][:cache_control]).to eq({ type: "ephemeral" })
    end

    it "never asks for tag output (allergen/diet stay code-derived, cuisine is Jev's)" do
      expect(described_class::SYSTEM_INSTRUCTIONS).not_to match(/allergen|diet|cuisine/i)
      expect(Ingestion::GapFillSchema.dig(:properties, :items, :items, :properties).keys)
        .to contain_exactly(:index, :ingredients)
    end
  end
end
