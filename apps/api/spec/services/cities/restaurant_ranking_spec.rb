require "rails_helper"

# Phase 5.6 — guards the city + dietary-preset ranking that backs
# the SSR /durango/[diet] SEO pages. Hits a real Postgres so the
# `&&` (overlap) operator + `FILTER (WHERE ...)` aggregation behave
# the same as production.
RSpec.describe Cities::RestaurantRanking do
  let(:city)  { create(:city, slug: "durango", name: "Durango", region: "CO") }
  let(:other_city) { create(:city, slug: "telluride", name: "Telluride", region: "CO") }

  let!(:beef)   { create(:ingredient, slug: "meat-beef") }
  let!(:cheese) { create(:ingredient, slug: "dairy-cheese") }
  let!(:salmon) { create(:ingredient, slug: "fish-salmon") }
  let!(:vegan_tag)   { create(:tag, slug: "diet-vegan") }
  let!(:dairy_tag)   { create(:tag, slug: "allergen-contains-dairy") }

  # Vegan preset: avoid dairy ingredient + the contains-dairy tag.
  let(:vegan_preset) do
    preset = create(:dietary_profile, slug: "vegan")
    create(:dietary_profile_ingredient, dietary_profile: preset, ingredient: cheese, rule: "avoid")
    create(:dietary_profile_tag,        dietary_profile: preset, tag: dairy_tag,    rule: "avoid")
    preset
  end

  let(:empty_preset) { create(:dietary_profile, slug: "balanced") }

  # Two restaurants in Durango, one in Telluride.
  let!(:tacos)     { create(:restaurant, :published, slug: "tacos", name: "Tacos", city: city) }
  let!(:cream)     { create(:restaurant, :published, slug: "cream", name: "Cream", city: city) }
  let!(:far_away)  { create(:restaurant, :published, slug: "far",   name: "Far Away", city: other_city) }

  before do
    # Tacos: 2 vegan-safe items + 1 dairy item.
    create(:item, :published, :confirmed, restaurant: tacos, name: "Veggie Taco", ingredients: [], tag_list: [])
    create(:item, :published, :confirmed, restaurant: tacos, name: "Bean Taco",   ingredients: [], tag_list: [])
    create(:item, :published, :confirmed, restaurant: tacos, name: "Beef Cheese Taco",
           ingredients: [beef, cheese], tag_list: [dairy_tag])

    # Cream: 1 dairy item, 0 vegan-safe.
    create(:item, :published, :confirmed, restaurant: cream, name: "Mac and Cheese",
           ingredients: [cheese], tag_list: [dairy_tag])

    # Far Away: 5 vegan items but in Telluride, not Durango — must not appear.
    5.times { |i| create(:item, :published, :confirmed, restaurant: far_away, name: "FA #{i}") }
  end

  describe "#call" do
    it "returns Durango restaurants only, ranked by visible_count desc" do
      ranked = described_class.new(city: city, dietary_profile: vegan_preset).call

      expect(ranked.map { |r| r.restaurant.slug }).to eq(%w[tacos cream])
      expect(ranked.first.visible_count).to eq(2)
      expect(ranked.first.total_count).to eq(3)
      expect(ranked.first.hidden_count).to eq(1)

      expect(ranked.last.visible_count).to eq(0)
      expect(ranked.last.total_count).to eq(1)
    end

    it "tiebreaks alphabetically by restaurant name" do
      # Wipe Tacos's items so both Durango restaurants tie at 0 visible.
      tacos.items.destroy_all

      ranked = described_class.new(city: city, dietary_profile: vegan_preset).call

      # Cream alphabetically before Tacos.
      expect(ranked.map { |r| r.restaurant.slug }).to eq(%w[cream tacos])
    end

    it "returns every restaurant when the preset has no avoid lists" do
      ranked = described_class.new(city: city, dietary_profile: empty_preset).call

      # Both Durango restaurants present; visible_count == total_count.
      expect(ranked.map { |r| [r.restaurant.slug, r.visible_count, r.total_count] }).to contain_exactly(
        ["tacos", 3, 3],
        ["cream", 1, 1]
      )
    end

    it "still returns restaurants with zero published items" do
      empty_restaurant = create(:restaurant, :published, slug: "empty", name: "Aaa Empty", city: city)
      _ = empty_restaurant
      ranked = described_class.new(city: city, dietary_profile: vegan_preset).call

      empty_row = ranked.find { |r| r.restaurant.slug == "empty" }
      expect(empty_row).not_to be_nil
      expect(empty_row.visible_count).to eq(0)
      expect(empty_row.total_count).to eq(0)
    end

    it "ignores draft restaurants (status != 'published')" do
      create(:restaurant, slug: "draft-spot", name: "Draft", city: city) # default status: draft
      ranked = described_class.new(city: city, dietary_profile: vegan_preset).call

      expect(ranked.map { |r| r.restaurant.slug }).not_to include("draft-spot")
    end
  end

  # `visible_count` is a public promise: the /durango/[diet] card says
  # "4 dishes you can eat" and the restaurant page has to agree. These
  # two pin where the ranking matches Menus::Filter and where it
  # deliberately does not.
  describe "agreement with the menu filter" do
    let!(:dairy_parent) { create(:ingredient, slug: "dairy") }

    it "expands an avoided parent to its subtree, like Menus::Filter does" do
      # Preset stores only the parent `dairy`; the dish carries the
      # child `dairy.cheese`. Comparing raw ids would call it visible
      # and over-count the SEO card against the menu the user opens.
      parent_preset = create(:dietary_profile, slug: "dairy-free")
      create(:dietary_profile_ingredient, dietary_profile: parent_preset,
                                          ingredient: dairy_parent, rule: "avoid")

      ranked = described_class.new(city: city, dietary_profile: parent_preset).call
      tacos_row = ranked.find { |r| r.restaurant.slug == "tacos" }

      # Beef Cheese Taco carries dairy.cheese and must be hidden.
      expect(tacos_row.visible_count).to eq(2)
      expect(tacos_row.total_count).to eq(3)

      menu_filter = Menus::Filter.build(preset_slug: "dairy-free")
      expect(menu_filter.avoid_ingredient_ids).to include(dairy_parent.id, cheese.id)
    end

    it "counts unconfirmed items as visible — a preset carries no strictness" do
      # The confidence rule fires only under strictness: "strict", which
      # belongs to a signed-in person. Both callers rank a DietaryProfile,
      # so this filter is balanced by construction and an AI-suggested
      # item counts exactly as Menus::Filter would count it.
      suggested = create(:restaurant, :published, slug: "suggested-spot", name: "Zed", city: city)
      item = create(:item, :published, restaurant: suggested, name: "Maybe Vegan Bowl")
      expect(item.confidence).to eq("suggested")

      ranked = described_class.new(city: city, dietary_profile: vegan_preset).call
      row = ranked.find { |r| r.restaurant.slug == "suggested-spot" }

      expect(row.visible_count).to eq(1)
      expect(Menus::Filter.build(preset_slug: "vegan").strictness).to eq("balanced")
      expect(Menus::Filter.build(preset_slug: "vegan").reasons_for(item, Menus::Labels::EMPTY)).to be_empty
    end
  end
end
