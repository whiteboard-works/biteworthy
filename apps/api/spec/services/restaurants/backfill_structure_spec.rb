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
          .to eq([ [ "small", 450 ], [ "large", 750 ] ])
        expect(result[:variants_added].first[:count]).to eq(2)
      end

      it "never overwrites existing variants" do
        item = create(:item, restaurant: restaurant, status: "published")
        ItemVariant.create!(item: item, size: "medium", price_cents: 600, position: 0)
        create(:ingestion_item,
               ingestion_run: run,
               decision: "accepted",
               item: item,
               prices_payload: [ { "size" => "large", "price_cents" => 800 } ])

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
               prices_payload: [ { "size" => "small", "price_cents" => 450 } ])

        result = described_class.new(restaurant: restaurant, dry_run: true).call

        expect(item.reload.menu_section).to be_nil
        expect(item.item_variants).to be_empty
        expect(result[:sections_created]).not_to be_empty
        expect(result[:variants_added]).not_to be_empty
      end
    end

    context "reorder" do
      let(:menu) { Menu.create!(restaurant: restaurant, name: "Main") }

      it "rewrites section and item positions from source order when dishes already have sections" do
        chicken = MenuSection.create!(menu: menu, name: "CHICKEN & LAMB", position: 0)
        starters = MenuSection.create!(menu: menu, name: "STARTERS", position: 1)

        item_a = create(:item, restaurant: restaurant, status: "published",
                               menu_section: starters, position: 0, name: "Samosa")
        item_b = create(:item, restaurant: restaurant, status: "published",
                               menu_section: chicken, position: 0, name: "Tikka")
        item_c = create(:item, restaurant: restaurant, status: "published",
                               menu_section: starters, position: 0, name: "Pakora")

        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item_a, section_name: "STARTERS", position: 0)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item_b, section_name: "CHICKEN & LAMB", position: 1)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item_c, section_name: "STARTERS", position: 2)

        result = described_class.new(restaurant: restaurant, reorder: true).call

        expect(starters.reload.position).to eq(0)
        expect(chicken.reload.position).to eq(1)
        expect(item_a.reload.position).to eq(0)
        expect(item_c.reload.position).to eq(1)
        expect(item_b.reload.position).to eq(0)
        expect(result[:sections_reordered]).to include(
          hash_including(name: "STARTERS", old_position: 1, new_position: 0),
          hash_including(name: "CHICKEN & LAMB", old_position: 0, new_position: 1)
        )
        expect(result[:items_reordered]).to include(
          hash_including(id: item_a.id, old_position: 0, new_position: 0),
          hash_including(id: item_c.id, old_position: 0, new_position: 1)
        )
      end

      it "never moves a dish to a different section or creates a section" do
        starters = MenuSection.create!(menu: menu, name: "STARTERS", position: 0)
        item = create(:item, restaurant: restaurant, status: "published",
                             menu_section: starters, position: 0)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item, section_name: "DIFFERENT", position: 0)

        expect {
          described_class.new(restaurant: restaurant, reorder: true).call
        }.not_to change { menu.menu_sections.count }

        expect(item.reload.menu_section).to eq(starters)
        expect(MenuSection.where(menu: menu, name: "DIFFERENT")).to be_empty
      end

      it "uses the latest accepted ingestion item per dish for source order" do
        chicken = MenuSection.create!(menu: menu, name: "CHICKEN & LAMB", position: 0)
        starters = MenuSection.create!(menu: menu, name: "STARTERS", position: 1)
        item = create(:item, restaurant: restaurant, status: "published",
                             menu_section: chicken, position: 0)
        other = create(:item, restaurant: restaurant, status: "published",
                              menu_section: starters, position: 0)

        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item, section_name: "CHICKEN & LAMB", position: 0, created_at: 2.days.ago)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item, section_name: "STARTERS", position: 5, created_at: 1.day.ago)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: other, section_name: "STARTERS", position: 1, created_at: 1.day.ago)

        described_class.new(restaurant: restaurant, reorder: true).call

        # Latest row for `item` is position 5, so STARTERS (other, pos 1) appears first.
        expect(starters.reload.position).to eq(0)
        expect(chicken.reload.position).to eq(1)
        expect(item.reload.menu_section).to eq(chicken)
      end

      it "keeps sections with no ingestion source after sourced ones, in their current order" do
        sides = MenuSection.create!(menu: menu, name: "SIDES", position: 0)
        dessert = MenuSection.create!(menu: menu, name: "DESSERTS", position: 1)
        chicken = MenuSection.create!(menu: menu, name: "CHICKEN & LAMB", position: 2)
        starters = MenuSection.create!(menu: menu, name: "STARTERS", position: 3)

        sourced = create(:item, restaurant: restaurant, status: "published",
                                menu_section: starters, position: 0)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: sourced, section_name: "STARTERS", position: 0)
        create(:item, restaurant: restaurant, status: "published",
                      menu_section: chicken, position: 0)
        create(:item, restaurant: restaurant, status: "published",
                      menu_section: sides, position: 0)
        create(:item, restaurant: restaurant, status: "published",
                      menu_section: dessert, position: 0)

        described_class.new(restaurant: restaurant, reorder: true).call

        expect(starters.reload.position).to eq(0)
        expect(sides.reload.position).to eq(1)
        expect(dessert.reload.position).to eq(2)
        expect(chicken.reload.position).to eq(3)
      end

      it "keeps items with no ingestion source after sourced items in the same section" do
        tacos = MenuSection.create!(menu: menu, name: "TACOS", position: 0)
        unsourced = create(:item, restaurant: restaurant, status: "published",
                                  menu_section: tacos, position: 0, name: "Manual taco")
        first = create(:item, restaurant: restaurant, status: "published",
                              menu_section: tacos, position: 0, name: "Carne")
        second = create(:item, restaurant: restaurant, status: "published",
                               menu_section: tacos, position: 0, name: "Pollo")

        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: first, section_name: "TACOS", position: 0)
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: second, section_name: "TACOS", position: 1)

        described_class.new(restaurant: restaurant, reorder: true).call

        expect(first.reload.position).to eq(0)
        expect(second.reload.position).to eq(1)
        expect(unsourced.reload.position).to eq(2)
        expect(unsourced.menu_section).to eq(tacos)
      end

      it "lists old and new positions on dry_run without writing" do
        starters = MenuSection.create!(menu: menu, name: "STARTERS", position: 3)
        item = create(:item, restaurant: restaurant, status: "published",
                             menu_section: starters, position: 7, name: "Samosa")
        create(:ingestion_item, ingestion_run: run, decision: "accepted",
               item: item, section_name: "STARTERS", position: 0)

        result = described_class.new(restaurant: restaurant, reorder: true, dry_run: true).call

        expect(result[:sections_reordered]).to include(
          hash_including(name: "STARTERS", old_position: 3, new_position: 0)
        )
        expect(result[:items_reordered]).to include(
          hash_including(name: "Samosa", old_position: 7, new_position: 0)
        )
        expect(starters.reload.position).to eq(3)
        expect(item.reload.position).to eq(7)
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
