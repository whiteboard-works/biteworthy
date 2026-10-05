require "rails_helper"

RSpec.describe Restaurants::Create do
  let(:user) { create(:user) }
  let(:city) { create(:city, slug: "durango", name: "Durango", region: "Colorado") }

  describe ".call" do
    context "duplicate detection with street addresses" do
      it "allows different restaurants with generic shared terms and different streets" do
        # Create "Nini's Taqueria" on Main St
        existing = create(:restaurant, :published, name: "Nini's Taqueria", city: city)
        RestaurantAddress.create!(restaurant: existing, street: "123 Main St", city: city.name, region: city.region)

        # Try to create "Zia Taqueria" on Oak St - should succeed
        result = described_class.call(
          name: "Zia Taqueria",
          city_slug: city.slug,
          creator: user,
          street: "456 Oak St"
        )

        expect(result.duplicate?).to be false
        expect(result.restaurant).to be_persisted
        expect(result.restaurant.name).to eq("Zia Taqueria")
      end

      it "flags possible duplicates when names are very similar even with different streets" do
        # Create "Red Iguana" on Main St
        existing = create(:restaurant, :published, name: "Red Iguana", city: city)
        RestaurantAddress.create!(restaurant: existing, street: "123 Main St", city: city.name, region: city.region)

        # Try to create "Red Iguana" (exact match) on Oak St - should flag as duplicate
        result = described_class.call(
          name: "Red Iguana",
          city_slug: city.slug,
          creator: user,
          street: "456 Oak St"
        )

        expect(result.duplicate?).to be true
        expect(result.candidates).not_to be_empty
      end

      it "flags duplicates when names are very similar on the same street" do
        # Create "Maria's Tacos" on Main St
        existing = create(:restaurant, :published, name: "Maria's Tacos", city: city)
        RestaurantAddress.create!(restaurant: existing, street: "123 Main St", city: city.name, region: city.region)

        # Try to create "Marias Taco" on same street - should flag as duplicate
        result = described_class.call(
          name: "Marias Taco",
          city_slug: city.slug,
          creator: user,
          street: "123 Main Street"
        )

        expect(result.duplicate?).to be true
        expect(result.candidates.first[:name]).to eq("Maria's Tacos")
      end

      it "allows creation with force flag even when duplicate detected" do
        # Create existing restaurant
        existing = create(:restaurant, :published, name: "Zia Taqueria", city: city)
        RestaurantAddress.create!(restaurant: existing, street: "123 Main St", city: city.name, region: city.region)

        # Force creation of similar name
        result = described_class.call(
          name: "Zia's Taqueria",
          city_slug: city.slug,
          creator: user,
          street: "123 Main St",
          force: true
        )

        expect(result.duplicate?).to be false
        expect(result.restaurant).to be_persisted
      end

      it "handles comparison when candidate has no address" do
        # Create restaurant without address
        create(:restaurant, :published, name: "Generic Taqueria", city: city)

        # Try to create similar named restaurant with address
        result = described_class.call(
          name: "Another Taqueria",
          city_slug: city.slug,
          creator: user,
          street: "123 Main St"
        )

        # Should use base threshold since candidate has no address
        expect(result.duplicate?).to be false
        expect(result.restaurant).to be_persisted
      end

      it "normalizes street addresses for comparison" do
        # Create restaurant on "Main Street"
        existing = create(:restaurant, :published, name: "Coffee Shop", city: city)
        RestaurantAddress.create!(restaurant: existing, street: "123 Main Street", city: city.name, region: city.region)

        # Try to create on "Main St" (abbreviation) - should recognize as same street
        result = described_class.call(
          name: "Coffee House",
          city_slug: city.slug,
          creator: user,
          street: "123 Main St"
        )

        # Low similarity names on same street should pass
        expect(result.duplicate?).to be false
        expect(result.restaurant).to be_persisted
      end
    end

    describe ".normalize_street" do
      it "standardizes street abbreviations" do
        expect(described_class.send(:normalize_street, "123 Main Street")).to eq("123 main st")
        expect(described_class.send(:normalize_street, "456 Oak Ave")).to eq("456 oak ave")
        expect(described_class.send(:normalize_street, "789 First Boulevard")).to eq("789 first blvd")
      end

      it "removes punctuation and normalizes whitespace" do
        expect(described_class.send(:normalize_street, "123  Main  St.")).to eq("123 main st")
        expect(described_class.send(:normalize_street, "456, Oak Ave.")).to eq("456 oak ave")
      end

      it "treats Street and St as equivalent" do
        normalized_street = described_class.send(:normalize_street, "123 Main Street")
        normalized_st = described_class.send(:normalize_street, "123 Main St")
        expect(normalized_street).to eq(normalized_st)
      end
    end
  end
end
