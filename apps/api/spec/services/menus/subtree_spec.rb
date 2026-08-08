require "rails_helper"

# The taxonomy is hierarchical for a reason, and until this shipped the
# filter ignored the hierarchy entirely: a person who said "I avoid dairy"
# was shown a dish tagged `dairy-cheddar` as visible.
#
# That is the product's whole safety claim failing in the most ordinary
# case there is — `dairy` is `allergen: true`, it is what `search_taxonomy`
# returns for "dairy", and it is what anyone would pick.
RSpec.describe Menus::Subtree do
  let!(:dairy)   { create(:ingredient, slug: "dairy", name: "Dairy", path: "dairy", allergen: true) }
  let!(:cheddar) { create(:ingredient, slug: "dairy-cheddar", name: "Cheddar", path: "dairy.cheddar") }
  let!(:brie)    { create(:ingredient, slug: "dairy-brie", name: "Brie", path: "dairy.brie") }
  let!(:peanut)  { create(:ingredient, slug: "nut-peanut", name: "Peanut", path: "nut.peanut") }

  describe ".ingredient_ids" do
    it "pulls in everything under an avoided parent" do
      expect(described_class.ingredient_ids([dairy.id])).to match_array([dairy.id, cheddar.id, brie.id])
    end

    it "leaves a leaf alone" do
      expect(described_class.ingredient_ids([cheddar.id])).to eq([cheddar.id])
    end

    it "does not reach sideways into another branch" do
      expect(described_class.ingredient_ids([dairy.id])).not_to include(peanut.id)
    end

    it "handles an empty list without a query" do
      expect(described_class.ingredient_ids([])).to eq([])
      expect(described_class.ingredient_ids(nil)).to eq([])
    end

    # Presets are stored pre-expanded, which is the workaround that proved
    # the filter never did this itself. Re-expanding must be a no-op.
    it "is idempotent" do
      once  = described_class.ingredient_ids([dairy.id])
      twice = described_class.ingredient_ids(once)

      expect(twice).to match_array(once)
    end

    # Ids that no longer resolve are already tolerated everywhere else
    # profiles are read; expansion must not be the thing that raises.
    it "ignores an id that no longer exists" do
      expect { described_class.ingredient_ids([SecureRandom.uuid]) }.not_to raise_error
    end
  end

  # The behaviour that actually matters, end to end through the real
  # filter: the dish has cheddar, the person avoids dairy, the dish is
  # hidden and says why.
  describe "through the filter" do
    let(:user)       { create(:user) }
    let(:city)       { create(:city) }
    let(:restaurant) { create(:restaurant, :published, city: city) }
    let!(:quesadilla) do
      create(:item, :published, restaurant: restaurant, name: "Cheese Quesadilla").tap do |item|
        # Written through the join, never the denormalized array — the
        # callbacks on ItemIngredient are what keep the two in sync.
        ItemIngredient.create!(item: item, ingredient: cheddar, confidence: "confirmed", source: "human")
      end
    end

    it "hides a dish whose ingredient sits under the avoided node" do
      user.profile.update!(avoid_ingredient_ids: [dairy.id], strictness: "balanced")

      filter = Menus::Filter.build(user: user)
      result = Menus::Query.new(restaurant: restaurant, filter: filter).call
      dish   = result[:items].find { |i| i[:id] == quesadilla.id }

      expect(dish[:status]).to eq("hidden")
      # And it still says why — a hidden dish that cannot explain itself is
      # the failure this product exists to avoid.
      expect(dish[:reasons].join(" ")).to match(/cheddar/i)
    end
  end
end
