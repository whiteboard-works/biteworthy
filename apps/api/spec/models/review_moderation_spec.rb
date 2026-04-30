require "rails_helper"

RSpec.describe Review, type: :model do
  let(:reviewer) { create(:user) }
  let(:item)     { create(:item, :published) }

  describe "scopes" do
    let!(:visible) { create(:review, item: item, user: reviewer) }
    let!(:hidden)  { create(:review, item: item, user: create(:user)).tap { |r| r.hide!(reason: "spam") } }
    let!(:flagged) do
      r = create(:review, item: item, user: create(:user), body: "Loved it.")
      r.update!(flagged_at: Time.current)
      r
    end

    it ".visible returns only non-hidden" do
      expect(described_class.visible).to contain_exactly(visible, flagged)
    end

    it ".hidden returns only hidden" do
      expect(described_class.hidden).to contain_exactly(hidden)
    end

    it ".awaiting_moderation returns flagged + not-hidden" do
      expect(described_class.awaiting_moderation).to contain_exactly(flagged)
    end
  end

  describe "#suspicious?" do
    it "flags URLs in the body" do
      expect(build(:review, body: "Check https://spam.example/promo").suspicious?).to be(true)
      expect(build(:review, body: "go to www.example.com bro").suspicious?).to be(true)
    end

    it "flags profanity word-boundaries (not substring matches)" do
      expect(build(:review, body: "Total fuck of a meal").suspicious?).to be(true)
      # No false positive on substring containment.
      expect(build(:review, body: "I love these ducks").suspicious?).to be(false)
    end

    it "ignores empty bodies" do
      expect(build(:review, body: "").suspicious?).to be(false)
      expect(build(:review, body: nil).suspicious?).to be(false)
    end

    it "leaves benign reviews alone" do
      expect(build(:review, body: "Best taco I've had in town.").suspicious?).to be(false)
    end
  end

  describe "auto-flagging on save" do
    it "sets flagged_at when the body is suspicious" do
      review = create(:review, item: item, user: reviewer, body: "Check https://spam.example/")
      expect(review.flagged_at).to be_present
    end

    it "does not flag a benign body" do
      review = create(:review, item: item, user: reviewer, body: "Tasty.")
      expect(review.flagged_at).to be_nil
    end

    it "is idempotent — re-saving doesn't bump the timestamp" do
      review = create(:review, item: item, user: reviewer, body: "spam at https://x/")
      first  = review.flagged_at
      review.update!(rating: 2)
      expect(review.reload.flagged_at).to eq(first)
    end
  end

  describe "#hide! / #unhide!" do
    let!(:review) { create(:review, item: item, user: reviewer, body: "Loved it.") }

    it "sets hidden_at + reason and clears flagged_at" do
      review.update!(flagged_at: Time.current)
      review.hide!(reason: "spam")
      expect(review.reload.hidden_at).to be_present
      expect(review.hidden_reason).to eq("spam")
      expect(review.flagged_at).to be_nil
    end

    it "raises on an unknown reason" do
      expect { review.hide!(reason: "bogus") }.to raise_error(ArgumentError)
    end

    it "#unhide! resets all moderation fields" do
      review.hide!(reason: "spam")
      review.unhide!
      expect(review.reload.hidden_at).to be_nil
      expect(review.hidden_reason).to be_nil
      expect(review.flagged_at).to be_nil
    end
  end

  describe "validations" do
    it "rejects an unknown hidden_reason" do
      review = build(:review, hidden_at: Time.current, hidden_reason: "wat")
      expect(review).not_to be_valid
      expect(review.errors[:hidden_reason]).to be_present
    end
  end
end
