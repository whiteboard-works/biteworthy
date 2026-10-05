# frozen_string_literal: true

require "rails_helper"

RSpec.describe Restaurants::BackfillStructure do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, restaurant: restaurant, status: "staged") }

  describe "#call" do
    context "sections" do
      it "creates MenuSections from accepted IngestionItems with section_name" do
        item = create(:item, restaurant: restaurant, status: "published", menu_section: nil)
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               section_name: "Appetizers")

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.menu_section).to be_present
        expect(item.menu_section.name).to eq("Appetizers")
        expect(result[:sections_created].size).to eq(1)
        expect(result[:sections_created].first[:section_name]).to eq("Appetizers")
      end

      it "never overwrites an existing menu_section_id" do
        menu = Menu.create!(restaurant: restaurant, name: "Main")
        section = MenuSection.create!(menu: menu, name: "Existing Section")
        item = create(:item, restaurant: restaurant, status: "published", menu_section: section)
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               section_name: "Different Section")

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.menu_section).to eq(section)
        expect(result[:sections_created]).to be_empty
      end

      it "reuses existing MenuSection by name" do
        menu = Menu.create!(restaurant: restaurant, name: "Main")
        existing_section = MenuSection.create!(menu: menu, name: "Tacos")

        item1 = create(:item, restaurant: restaurant, status: "published")
        item2 = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item, ingestion_run: run, decision: "accepted", item: item1, section_name: "Tacos")
        create(:ingestion_item, ingestion_run: run, decision: "accepted", item: item2, section_name: "Tacos")

        described_class.new(restaurant: restaurant).call

        expect(item1.reload.menu_section).to eq(existing_section)
        expect(item2.reload.menu_section).to eq(existing_section)
        expect(menu.reload.menu_sections.count).to eq(1)
      end

      it "skips items without section_name" do
        item = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item, ingestion_run: run, decision: "accepted", item: item, section_name: nil)

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.menu_section).to be_nil
        expect(result[:sections_created]).to be_empty
      end
    end

    context "variants" do
      it "creates ItemVariants from prices_payload when item has none" do
        item = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               prices_payload: [
                 { "size" => "small", "price_cents" => 450 },
                 { "size" => "large", "price_cents" => 750 }
               ])

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.item_variants.count).to eq(2)
        expect(item.item_variants.order(:position).pluck(:size, :price_cents))
          .to eq([["small", 450], ["large", 750]])
        expect(result[:variants_added].first[:count]).to eq(2)
      end

      it "never overwrites existing variants" do
        item = create(:item, restaurant: restaurant, status: "published")
        ItemVariant.create!(item: item, size: "medium", price_cents: 600, position: 0)
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               prices_payload: [{ "size" => "large", "price_cents" => 800 }])

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.item_variants.count).to eq(1)
        expect(item.item_variants.first.price_cents).to eq(600)
        expect(result[:variants_added]).to be_empty
      end

      it "skips items without prices_payload" do
        item = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item, ingestion_run: run, decision: "accepted", item: item, prices_payload: nil)

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.item_variants).to be_empty
        expect(result[:variants_added]).to be_empty
      end

      it "skips price rows without price_cents" do
        item = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               prices_payload: [
                 { "size" => "market", "price_cents" => nil },
                 { "size" => "regular", "price_cents" => 500 }
               ])

        result = described_class.new(restaurant: restaurant).call

        expect(item.reload.item_variants.count).to eq(1)
        expect(item.item_variants.first.size).to eq("regular")
      end
    end

    context "dry_run mode" do
      it "rolls back all changes when dry_run is true" do
        item = create(:item, restaurant: restaurant, status: "published")
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               section_name: "Tacos",
               prices_payload: [{ "size" => "small", "price_cents" => 450 }])

        result = described_class.new(restaurant: restaurant, dry_run: true).call

        expect(item.reload.menu_section).to be_nil
        expect(item.item_variants).to be_empty
        expect(result[:sections_created]).not_to be_empty
        expect(result[:variants_added]).not_to be_empty
      end
    end

    context "only accepted items" do
      it "ignores pending, rejected, and edited items" do
        accepted_item = create(:item, restaurant: restaurant, status: "published")
        pending_item  = create(:item, restaurant: restaurant, status: "published")
        rejected_item = create(:item, restaurant: restaurant, status: "published")

        create(:ingestion_item, ingestion_run: run, decision: "accepted", item: accepted_item, section_name: "A")
        create(:ingestion_item, ingestion_run: run, decision: "pending", item: pending_item, section_name: "B")
        create(:ingestion_item, ingestion_run: run, decision: "rejected", item: rejected_item, section_name: "C")

        result = described_class.new(restaurant: restaurant).call

        expect(accepted_item.reload.menu_section&.name).to eq("A")
        expect(pending_item.reload.menu_section).to be_nil
        expect(rejected_item.reload.menu_section).to be_nil
        expect(result[:sections_created].size).to eq(1)
      end
    end
  end
end
