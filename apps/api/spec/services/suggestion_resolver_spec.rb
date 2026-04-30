require "rails_helper"

RSpec.describe SuggestionResolver do
  let(:moderator) { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)      { create(:item, :published, restaurant: restaurant, name: "Carne Asada Taco") }
  let(:cilantro)  { create(:ingredient, slug: "herb-cilantro") }
  let(:spicy_tag) { create(:tag, slug: "flavor-spicy") }

  def suggestion(kind:, payload: {})
    Suggestion.create!(
      user: create(:user), subject: item, kind: kind, status: "pending", payload: payload
    )
  end

  describe ".accept!" do
    it "add_ingredient creates an ItemIngredient with confidence:confirmed source:human" do
      sg = suggestion(kind: "add_ingredient", payload: { "ingredient_slug" => cilantro.slug })

      described_class.accept!(sg, by_user: moderator)

      ii = item.item_ingredients.find_by(ingredient: cilantro)
      expect(ii).to be_present
      expect(ii.confidence).to eq("confirmed")
      expect(ii.source).to     eq("human")
      sg.reload
      expect(sg.status).to eq("accepted")
      expect(sg.resolved_by_user_id).to eq(moderator.id)
    end

    it "add_ingredient is idempotent (re-accepting an already-applied suggestion doesn't dup)" do
      sg = suggestion(kind: "add_ingredient", payload: { "ingredient_id" => cilantro.id })
      described_class.accept!(sg, by_user: moderator)
      expect {
        # Re-creating + re-applying with the same payload also doesn't dup.
        described_class.accept!(suggestion(kind: "add_ingredient", payload: { "ingredient_id" => cilantro.id }), by_user: moderator)
      }.not_to change { item.item_ingredients.where(ingredient: cilantro).count }
    end

    it "remove_ingredient deletes the join row" do
      ItemIngredient.create!(item: item, ingredient: cilantro, confidence: "confirmed", source: "human")
      sg = suggestion(kind: "remove_ingredient", payload: { "ingredient_slug" => cilantro.slug })

      described_class.accept!(sg, by_user: moderator)
      expect(item.item_ingredients.where(ingredient: cilantro)).to be_empty
    end

    it "add_tag creates an ItemTag with confidence:confirmed source:human" do
      sg = suggestion(kind: "add_tag", payload: { "tag_slug" => spicy_tag.slug })
      described_class.accept!(sg, by_user: moderator)
      it_tag = item.item_tags.find_by(tag: spicy_tag)
      expect(it_tag.confidence).to eq("confirmed")
      expect(it_tag.source).to     eq("human")
    end

    it "remove_tag deletes the join row" do
      ItemTag.create!(item: item, tag: spicy_tag, confidence: "confirmed", source: "human")
      sg = suggestion(kind: "remove_tag", payload: { "tag_id" => spicy_tag.id })
      described_class.accept!(sg, by_user: moderator)
      expect(item.item_tags.where(tag: spicy_tag)).to be_empty
    end

    it "rename updates Item#name" do
      sg = suggestion(kind: "rename", payload: { "name" => "Carne Asada al Pastor Taco" })
      described_class.accept!(sg, by_user: moderator)
      expect(item.reload.name).to eq("Carne Asada al Pastor Taco")
    end

    it "raises InvalidPayloadError on a blank rename" do
      sg = suggestion(kind: "rename", payload: { "name" => "  " })
      expect { described_class.accept!(sg, by_user: moderator) }.to raise_error(SuggestionResolver::InvalidPayloadError)
      expect(sg.reload.status).to eq("pending") # transaction rolled back
    end

    it "raises InvalidPayloadError when the ingredient can't be found" do
      sg = suggestion(kind: "add_ingredient", payload: { "ingredient_slug" => "no-such-thing" })
      expect { described_class.accept!(sg, by_user: moderator) }.to raise_error(SuggestionResolver::InvalidPayloadError)
    end

    it "raises UnsupportedKindError on a kind we don't know" do
      sg = suggestion(kind: "claim", payload: {}) # claim is for restaurants, not items
      expect { described_class.accept!(sg, by_user: moderator) }.to raise_error(SuggestionResolver::UnsupportedKindError)
    end
  end

  describe ".reject!" do
    it "marks rejected and stamps the resolver, no Item changes" do
      sg = suggestion(kind: "rename", payload: { "name" => "WHATEVER" })
      expect {
        described_class.reject!(sg, by_user: moderator)
      }.not_to change { item.reload.name }
      sg.reload
      expect(sg.status).to eq("rejected")
      expect(sg.resolved_by_user_id).to eq(moderator.id)
    end
  end
end
