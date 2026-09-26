require "rails_helper"

# Favorites and a user's own ratings are the "no taste quiz needed" path
# to Top Picks — see Menus::Filter#taste_signals_for, which folds this
# in underneath the explicit profile. This spec pins the derivation
# rules in isolation, before any merging with the explicit profile.
RSpec.describe Menus::ImplicitTasteSignals do
  let(:restaurant) { create(:restaurant, :published) }
  let(:user)       { create(:user) }
  let(:spicy)      { create(:tag, slug: "flavor-spicy", name: "Spicy") }
  let(:basil)      { create(:ingredient, slug: "herb-basil", name: "Basil") }

  describe ".for_user" do
    it "returns nothing for a user with no favorites and no reviews" do
      signals = described_class.for_user(user)

      expect(signals.liked_tag_ids).to be_empty
      expect(signals.liked_ingredient_ids).to be_empty
      expect(signals.disliked_tag_ids).to be_empty
      expect(signals.disliked_ingredient_ids).to be_empty
    end

    it "treats a favorited dish's tags/ingredients as liked" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ], ingredients: [ basil ])
      create(:favorite_item, user: user, item: dish)

      signals = described_class.for_user(user)

      expect(signals.liked_tag_ids).to eq([ spicy.id ])
      expect(signals.liked_ingredient_ids).to eq([ basil.id ])
    end

    it "treats a dish rated 4 or 5 as liked" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:review, user: user, item: dish, rating: 4)

      expect(described_class.for_user(user).liked_tag_ids).to eq([ spicy.id ])
    end

    it "treats a dish rated 1 or 2 as disliked" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:review, user: user, item: dish, rating: 2)

      expect(described_class.for_user(user).disliked_tag_ids).to eq([ spicy.id ])
    end

    it "ignores a middling (3-star) review — no signal either way" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:review, user: user, item: dish, rating: 3)

      signals = described_class.for_user(user)
      expect(signals.liked_tag_ids).to be_empty
      expect(signals.disliked_tag_ids).to be_empty
    end

    it "ignores another user's favorites and reviews" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:favorite_item, user: create(:user), item: dish)
      create(:review, user: create(:user), item: dish, rating: 5)

      expect(described_class.for_user(user).liked_tag_ids).to be_empty
    end

    it "ignores a hidden (moderated) review" do
      dish = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:review, user: user, item: dish, rating: 5, hidden_at: Time.current)

      expect(described_class.for_user(user).liked_tag_ids).to be_empty
    end

    # Favoriting one spicy dish and rating a different spicy dish a 1
    # is contradictory activity — it is not read as a signal in either
    # direction rather than arbitrarily picking a winner.
    it "cancels a tag that its own activity calls both ways" do
      loved   = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      hated   = create(:item, :published, restaurant: restaurant, tag_list: [ spicy ])
      create(:favorite_item, user: user, item: loved)
      create(:review, user: user, item: hated, rating: 1)

      signals = described_class.for_user(user)
      expect(signals.liked_tag_ids).to be_empty
      expect(signals.disliked_tag_ids).to be_empty
    end
  end
end
