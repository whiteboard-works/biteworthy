require "rails_helper"

# `reasons_for` is the product's entire safety claim in one method: a dish
# the caller cannot eat comes back with the reasons it cannot, never dropped
# and never bare. It is also now the ONLY implementation of that rule — the
# hand-mirrored TypeScript copy went away with this change — so the coverage
# it used to share has to live here rather than being implied by the request
# specs that happen to exercise it end to end.
RSpec.describe Menus::Filter do
  let(:restaurant) { create(:restaurant, :published) }
  let!(:cheddar)   { create(:ingredient, name: "Cheddar", slug: "dairy-cheddar", path: "dairy.cheddar") }
  let!(:peanut)    { create(:ingredient, name: "Peanut",  slug: "nut-peanut",    path: "nut.peanut") }
  let!(:dairy_tag) { create(:tag, name: "Contains dairy", slug: "allergen-contains-dairy", family: "allergen") }

  def filter_for(avoid_ingredients: [], avoid_tags: [], strictness: "balanced")
    described_class.new(
      avoid_ingredient_ids: avoid_ingredients.map(&:id),
      avoid_tag_ids:        avoid_tags.map(&:id),
      strictness:           strictness,
      source:               "user_profile",
      preset_slug:          nil
    )
  end

  def reasons(item, filter)
    filter.reasons_for(item, Menus::Labels.for_filter([item], filter))
  end

  describe "#reasons_for" do
    it "returns no reasons for a dish that carries nothing the caller avoids" do
      item = create(:item, :published, restaurant: restaurant, ingredients: [peanut])

      expect(reasons(item, filter_for(avoid_ingredients: [cheddar]))).to be_empty
    end

    # The display strings ride along so the client's chip is a pure render.
    # Dropping them would cost a lookup per reason at exactly the moment
    # someone is deciding whether a dish is safe.
    it "names the avoided ingredient and its family" do
      item = create(:item, :published, restaurant: restaurant, ingredients: [cheddar])

      expect(reasons(item, filter_for(avoid_ingredients: [cheddar]))).to eq([
        { kind: "avoid_ingredient", ingredient_id: cheddar.id,
          ingredient_name: "Cheddar", ingredient_family: "dairy" }
      ])
    end

    it "names the avoided tag and its family" do
      item = create(:item, :published, restaurant: restaurant, tags: [dairy_tag])

      expect(reasons(item, filter_for(avoid_tags: [dairy_tag]))).to eq([
        { kind: "avoid_tag", tag_id: dairy_tag.id,
          tag_name: "Contains dairy", tag_family: "allergen" }
      ])
    end

    # Every reason, not the first one. A dish hidden for two reasons that
    # only admits to one invites "well, I'll just avoid the cheese".
    it "reports every reason a dish is hidden, ingredients before tags" do
      item = create(:item, :published, restaurant: restaurant,
                                       ingredients: [cheddar], tags: [dairy_tag])

      result = reasons(item, filter_for(avoid_ingredients: [cheddar], avoid_tags: [dairy_tag]))

      expect(result.map { |r| r[:kind] }).to eq(%w[avoid_ingredient avoid_tag])
    end

    context "strict mode" do
      # Strict mode is for someone with a real allergy: an association we
      # merely inferred is not evidence enough to call a dish safe.
      it "hides a dish whose data is not confirmed" do
        item = create(:item, :published, restaurant: restaurant, confidence: "suggested")

        expect(reasons(item, filter_for(strictness: "strict")))
          .to eq([{ kind: "unconfirmed_strict", confidence: "suggested" }])
      end

      it "leaves a confirmed dish alone" do
        item = create(:item, :published, restaurant: restaurant, confidence: "confirmed")

        expect(reasons(item, filter_for(strictness: "strict"))).to be_empty
      end

      # `relaxed` and `balanced` are byte-identical in the engine — only
      # `strict` branches. The onboarding copy implies otherwise, and this
      # is the line that says which one is true.
      it "applies no confidence rule below strict" do
        item = create(:item, :published, restaurant: restaurant, confidence: "inferred")

        %w[relaxed balanced].each do |strictness|
          expect(reasons(item, filter_for(strictness: strictness))).to be_empty
        end
      end
    end

    # A stale id in someone's avoid list must not blow up the menu, and must
    # not silently stop hiding either — the reason still fires, unnamed.
    it "still cites an avoided id whose taxonomy row has gone" do
      item   = create(:item, :published, restaurant: restaurant, ingredients: [cheddar])
      filter = filter_for(avoid_ingredients: [cheddar])
      labels = Menus::Labels::EMPTY

      expect(filter.reasons_for(item, labels)).to eq([
        { kind: "avoid_ingredient", ingredient_id: cheddar.id,
          ingredient_name: nil, ingredient_family: nil }
      ])
    end
  end

  # The expansion lives in `build`, not in `reasons_for`, so that the rule
  # itself stays comparable across implementations. This pins the seam.
  describe ".build" do
    it "hides a dish tagged with a descendant of what the caller avoids" do
      dairy = create(:ingredient, name: "Dairy", slug: "dairy", path: "dairy")
      item  = create(:item, :published, restaurant: restaurant, ingredients: [cheddar])
      user  = create(:user)
      user.profile.update!(avoid_ingredient_ids: [dairy.id])

      filter = described_class.build(user: user)

      expect(filter.avoid_ingredient_ids).to include(cheddar.id)
      expect(reasons(item, filter).map { |r| r[:kind] }).to eq(["avoid_ingredient"])
    end

    it "prefers a share token over the signed-in caller's own profile" do
      user = create(:user)
      user.profile.update!(avoid_ingredient_ids: [peanut.id])
      token = ProfileToken.encode(avoid_ingredient_ids: [cheddar.id], avoid_tag_ids: [], strictness: "balanced")

      filter = described_class.build(user: user, profile_token: token)

      expect(filter.source).to eq("profile_token")
      expect(filter.avoid_ingredient_ids).to eq([cheddar.id])
    end
  end
end
