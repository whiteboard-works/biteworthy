require "rails_helper"

# Phase 6.4 — moderation lens + strict-mode graduation.
RSpec.describe Restaurant, type: :model do
  let(:scanner) { create(:user, password: "password123", is_admin: false) }

  describe ".community_published" do
    it "includes live community-created restaurants" do
      community_live  = create(:restaurant, :published, created_by_user: scanner)
      community_draft = create(:restaurant, status: "draft", created_by_user: scanner)
      admin_seeded    = create(:restaurant, :published) # no creator, no suggested items

      expect(described_class.community_published).to contain_exactly(community_live)
      expect(described_class.community_published).not_to include(community_draft, admin_seeded)
    end

    it "includes seeded restaurants that received a community RE-scan (suggested items, no creator)" do
      rescanned = create(:restaurant, :published) # admin-seeded
      create(:item, :published, restaurant: rescanned) # factory default confidence: suggested

      pristine = create(:restaurant, :published)
      create(:item, :published, :confirmed, restaurant: pristine)

      expect(described_class.community_published).to contain_exactly(rescanned)
    end
  end

  describe "#confirm_community_associations!" do
    let(:restaurant) { create(:restaurant, :published, created_by_user: scanner) }
    let(:cheese)     { create(:ingredient, slug: "dairy-cheese") }
    let(:mexican)    { create(:tag, slug: "cuisine-mexican") }

    let!(:community_item) do
      # factory writes joins with confidence = item.confidence ("suggested")
      create(:item, :published, restaurant: restaurant,
                                ingredients: [cheese], tag_list: [mexican])
    end

    it "flips human-vouched suggested associations AND item confidence to confirmed" do
      counts = restaurant.confirm_community_associations!

      expect(counts).to eq(items: 1, ingredients: 1, tags: 1)
      expect(community_item.reload.confidence).to eq("confirmed")
      expect(ItemIngredient.where(item: community_item).pluck(:confidence)).to all(eq("confirmed"))
      expect(ItemTag.where(item: community_item).pluck(:confidence)).to        all(eq("confirmed"))
    end

    it "leaves ai-sourced suggestions alone AND keeps their item unconfirmed" do
      onion = create(:ingredient, slug: "vegetable-onion")
      ai_row = ItemIngredient.create!(item: community_item, ingredient: onion,
                                      confidence: "suggested", source: "ai")

      counts = restaurant.confirm_community_associations!

      expect(ai_row.reload.confidence).to eq("suggested")
      # The item must NOT graduate while an untrusted association
      # remains — strict mode keys off item.confidence (6.4.1).
      expect(community_item.reload.confidence).to eq("suggested")
      expect(counts[:items]).to eq(0)
    end

    it "does not touch other restaurants" do
      other_item = create(:item, :published, ingredients: [create(:ingredient, slug: "grain-wheat")])

      restaurant.confirm_community_associations!

      expect(other_item.reload.confidence).to eq("suggested")
      expect(ItemIngredient.where(item: other_item).pluck(:confidence)).to all(eq("suggested"))
    end

    it "keeps the denormalized id arrays intact (update_all skips callbacks by design)" do
      before_ids = community_item.reload.ingredient_ids

      restaurant.confirm_community_associations!

      expect(community_item.reload.ingredient_ids).to eq(before_ids)
    end
  end
end
