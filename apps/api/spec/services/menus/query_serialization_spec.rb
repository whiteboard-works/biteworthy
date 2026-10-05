# frozen_string_literal: true

require "rails_helper"

RSpec.describe Menus::Query, "serialization" do
  let(:restaurant) { create(:restaurant, :published) }
  let(:filter)     { Menus::Filter.new(avoid_ingredient_ids: [], avoid_tag_ids: []) }

  describe "variants serialization" do
    it "includes variants array with size, price_cents, and currency" do
      item = create(:item, restaurant: restaurant, name: "Burrito", status: "published")
      ItemVariant.create!(item: item, size: "small", price_cents: 850, currency: "USD", position: 0)
      ItemVariant.create!(item: item, size: "large", price_cents: 1150, currency: "USD", position: 1)

      query = described_class.new(restaurant: restaurant, filter: filter)
      result = query.call

      item_data = result[:items].find { |i| i[:id] == item.id }
      expect(item_data[:variants]).to eq([
        { size: "small", price_cents: 850, currency: "USD" },
        { size: "large", price_cents: 1150, currency: "USD" }
      ])
    end

    it "returns empty array when item has no variants" do
      item = create(:item, restaurant: restaurant, name: "Taco", status: "published")

      query = described_class.new(restaurant: restaurant, filter: filter)
      result = query.call

      item_data = result[:items].find { |i| i[:id] == item.id }
      expect(item_data[:variants]).to eq([])
    end

    it "preserves variant position order" do
      item = create(:item, restaurant: restaurant, name: "Soda", status: "published")
      ItemVariant.create!(item: item, size: "large", price_cents: 400, position: 2)
      ItemVariant.create!(item: item, size: "small", price_cents: 200, position: 0)
      ItemVariant.create!(item: item, size: "medium", price_cents: 300, position: 1)

      query = described_class.new(restaurant: restaurant, filter: filter)
      result = query.call

      item_data = result[:items].find { |i| i[:id] == item.id }
      expect(item_data[:variants].map { |v| v[:size] }).to eq(%w[small medium large])
    end
  end

  describe "section serialization" do
    it "includes menu_section_position when item has a section" do
      menu = Menu.create!(restaurant: restaurant, name: "Main")
      section = MenuSection.create!(menu: menu, name: "Appetizers", position: 2)
      item = create(:item, restaurant: restaurant, name: "Nachos", status: "published", menu_section: section)

      query = described_class.new(restaurant: restaurant, filter: filter)
      result = query.call

      item_data = result[:items].find { |i| i[:id] == item.id }
      expect(item_data[:menu_section_name]).to eq("Appetizers")
      expect(item_data[:menu_section_position]).to eq(2)
    end

    it "returns nil position when item has no section" do
      item = create(:item, restaurant: restaurant, name: "Special", status: "published")

      query = described_class.new(restaurant: restaurant, filter: filter)
      result = query.call

      item_data = result[:items].find { |i| i[:id] == item.id }
      expect(item_data[:menu_section_position]).to be_nil
    end
  end

  describe "N+1 queries" do
    it "does not trigger N+1 queries for variants" do
      5.times do |i|
        item = create(:item, restaurant: restaurant, name: "Item #{i}", status: "published")
        ItemVariant.create!(item: item, size: "small", price_cents: 500, position: 0)
      end

      query = described_class.new(restaurant: restaurant, filter: filter)

      expect do
        query.call
      end.not_to exceed_query_limit(12)
    end
  end
end
