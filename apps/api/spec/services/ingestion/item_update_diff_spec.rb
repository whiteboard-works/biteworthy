require "rails_helper"

RSpec.describe Ingestion::ItemUpdateDiff do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, restaurant: restaurant) }
  let(:item) do
    create(:item, restaurant: restaurant, name: "Carne Asada Taco",
                  description: "Grilled steak, cilantro, onion.")
  end

  let!(:beef)  { create(:ingredient, slug: "meat-beef") }
  let!(:onion) { create(:ingredient, slug: "vegetable-onion") }

  def staged(attrs = {})
    create(:ingestion_item, {
      ingestion_run: run,
      name: "Carne Asada Taco",
      description: item.description,
      ingredients_payload: [],
      tags_payload: [],
      prices_payload: []
    }.merge(attrs))
  end

  describe "description" do
    it "reports a change as from/to" do
      diff = described_class.call(staged(description: "Now with lime."), item)

      expect(diff[:description]).to eq(from: item.description, to: "Now with lime.")
      expect(diff[:no_changes]).to be false
    end

    it "never proposes blanking a description (absence of evidence)" do
      diff = described_class.call(staged(description: nil), item)
      expect(diff[:description]).to be_nil
    end

    it "ignores whitespace-only differences" do
      diff = described_class.call(staged(description: "  #{item.description}  "), item)
      expect(diff[:description]).to be_nil
    end
  end

  describe "prices" do
    before { ItemVariant.create!(item: item, size: "small", price_cents: 450, position: 0) }

    it "reports a changed price set as normalized from/to" do
      diff = described_class.call(
        staged(prices_payload: [{ "size" => "small", "price_cents" => 550 }]), item
      )

      expect(diff[:prices]).to eq(
        from: [{ size: "small", price_cents: 450 }],
        to:   [{ size: "small", price_cents: 550 }]
      )
    end

    it "never proposes deleting variants when the scan carries no prices" do
      diff = described_class.call(staged(prices_payload: []), item)
      expect(diff[:prices]).to be_nil
    end

    it "treats the same price set in a different order as unchanged" do
      ItemVariant.create!(item: item, size: "large", price_cents: 750, position: 1)

      diff = described_class.call(
        staged(prices_payload: [
                 { "size" => "large", "price_cents" => 750 },
                 { "size" => "small", "price_cents" => 450 }
               ]), item
      )
      expect(diff[:prices]).to be_nil
    end

    it "drops priceless rows before comparing" do
      diff = described_class.call(
        staged(prices_payload: [
                 { "size" => "market", "price_cents" => nil },
                 { "size" => "small", "price_cents" => 450 }
               ]), item
      )
      expect(diff[:prices]).to be_nil
    end
  end

  describe "added ingredients and tags" do
    before { ItemIngredient.create!(item: item, ingredient: beef, confidence: "confirmed", source: "human") }

    it "lists payload slugs the item doesn't have yet" do
      diff = described_class.call(
        staged(ingredients_payload: [
                 { "slug" => "meat-beef", "confidence" => 0.97 },
                 { "slug" => "vegetable-onion", "confidence" => 0.93 }
               ]), item
      )

      expect(diff[:added_ingredients]).to eq(["vegetable-onion"])
    end

    it "reports tags the same way" do
      tag = create(:tag, slug: "grilled")
      ItemTag.create!(item: item, tag: tag, confidence: "confirmed", source: "human")

      diff = described_class.call(
        staged(tags_payload: [
                 { "slug" => "grilled", "confidence" => 0.9 },
                 { "slug" => "spicy", "confidence" => 0.8 }
               ]), item
      )

      expect(diff[:added_tags]).to eq(["spicy"])
    end
  end

  it "flags no_changes when nothing differs" do
    diff = described_class.call(staged, item)

    expect(diff).to eq(
      description: nil, prices: nil,
      added_ingredients: [], added_tags: [],
      no_changes: true
    )
  end
end
