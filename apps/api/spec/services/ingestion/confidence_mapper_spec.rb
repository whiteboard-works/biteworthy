# frozen_string_literal: true

require "rails_helper"

# ConfidenceMapper is the single implementation behind promote, backfill,
# and 766's IngestionItem#map_confidence delegate. Keyword-to-wheat
# (pizza → grain-wheat, source: derived) must stay suggested — never
# confirmed, even on admin accept — or Strict mode would treat an
# inferred crust as human-verified.
RSpec.describe Ingestion::ConfidenceMapper do
  describe ".map_confidence" do
    it "keeps 766 keyword-to-wheat derived rows at suggested for admin accept" do
      expect(described_class.map_confidence(0.8, "derived", "confirmed")).to eq("suggested")
    end

    it "maps an allergen tag inherited from derived wheat to suggested" do
      expect(
        described_class.map_confidence(0.8, "ingredient_derived", "confirmed", from_source: "derived")
      ).to eq("suggested")
    end

    it "maps an allergen tag inherited from AI at 0.85 to suggested" do
      expect(
        described_class.map_confidence(0.85, "ingredient_derived", "confirmed", from_source: "ai")
      ).to eq("suggested")
    end

    it "fails closed when ingredient_derived has no parent source" do
      expect(described_class.map_confidence(1.0, "ingredient_derived", "confirmed")).to eq("inferred")
    end
  end
end
