require "rails_helper"

RSpec.describe Avo::Actions::Reviews::Hide do
  let(:item) { create(:item, :published) }
  let!(:review_a) { create(:review, item: item, user: create(:user)) }
  let!(:review_b) { create(:review, item: item, user: create(:user)) }

  it "hides every passed review with the given reason" do
    hidden, skipped = described_class.hide_all([review_a, review_b], reason: "spam")
    expect(hidden).to eq(2)
    expect(skipped).to eq(0)
    [review_a, review_b].each do |r|
      r.reload
      expect(r.hidden_at).to be_present
      expect(r.hidden_reason).to eq("spam")
    end
  end

  it "skips already-hidden reviews and still hides the new ones" do
    review_a.hide!(reason: "off_topic")
    hidden, skipped = described_class.hide_all([review_a, review_b], reason: "spam")
    expect(hidden).to eq(1)
    expect(skipped).to eq(1)
    expect(review_a.reload.hidden_reason).to eq("off_topic") # unchanged
    expect(review_b.reload.hidden_reason).to eq("spam")
  end

  it "clears the moderation flag when hiding (queue empties out)" do
    review_a.update!(flagged_at: Time.current)
    described_class.hide_all([review_a], reason: "spam")
    expect(review_a.reload.flagged_at).to be_nil
  end
end

RSpec.describe Avo::Actions::Reviews::Unhide do
  let(:item) { create(:item, :published) }
  let!(:hidden_review) do
    create(:review, item: item, user: create(:user)).tap { |r| r.hide!(reason: "spam") }
  end
  let!(:visible_review) { create(:review, item: item, user: create(:user)) }

  it "restores hidden reviews and skips already-visible ones" do
    restored, skipped = described_class.unhide_all([hidden_review, visible_review])
    expect(restored).to eq(1)
    expect(skipped).to eq(1)
    expect(hidden_review.reload.hidden_at).to be_nil
    expect(hidden_review.hidden_reason).to be_nil
  end
end
