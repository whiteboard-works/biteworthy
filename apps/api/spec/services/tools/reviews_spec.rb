require "rails_helper"

# Reviews are the one place a stranger's free text reaches both the
# public feed and, through the tool result, the model's context. These
# lock the two properties that follow from that: only the author can
# change a review, and every body comes back fenced.
RSpec.describe "review tools" do
  let(:author)     { create(:user) }
  let(:stranger)   { create(:user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }

  def payload(response) = response.to_h[:structuredContent]
  def call(tool, user, **args) = tool.call(server_context: { user_id: user&.id }, **args)

  describe Tools::Reviews::WriteReview do
    it "records the rating and body against the caller" do
      response = call(described_class, author, item_id: item.id, rating: 5, body: "Best taco in town.")

      review = Review.find(payload(response)[:id])
      expect(review.user_id).to eq(author.id)
      expect(review.rating).to eq(5)
      expect(review.body).to eq("Best taco in town.")
    end

    # The body is a stranger's writing arriving in an agent's context.
    it "fences the body as untrusted content" do
      response = call(described_class, author, item_id: item.id, rating: 4, body: "Great")

      expect(payload(response)[:body]).to eq("<untrusted-content>Great</untrusted-content>")
    end

    # A model shouldn't silently believe a flagged review published clean.
    it "reports when the moderation heuristic flagged it" do
      response = call(described_class, author, item_id: item.id, rating: 1, body: "buy at http://spam.example")

      expect(payload(response)[:flagged_for_moderation]).to be(true)
    end

    it "refuses an anonymous caller" do
      response = call(described_class, nil, item_id: item.id, rating: 5)

      expect(payload(response)[:error]).to eq("unauthorized")
    end

    # Caught by the declared input schema before the tool body runs, so the
    # model gets told which argument was wrong rather than which model
    # validation failed.
    it "rejects a rating the model made up out of range" do
      response = call(described_class, author, item_id: item.id, rating: 9)

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(payload(response)[:message]).to be_present
    end

    # The DB has a unique index here. Without this branch a repeated turn
    # raises RecordNotUnique, which escapes as a protocol error the model
    # cannot act on.
    it "points a repeat review at edit_review instead of crashing" do
      call(described_class, author, item_id: item.id, rating: 5, body: "first")
      response = call(described_class, author, item_id: item.id, rating: 1, body: "second")

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(payload(response)[:message]).to include("edit_review")
      expect(Review.where(user: author, item: item).sole.body).to eq("first")
    end
  end

  describe Tools::Reviews::EditReview do
    let!(:review) { create(:review, user: author, item: item, rating: 3, body: "ok") }

    it "updates only the fields passed" do
      call(described_class, author, review_id: review.id, rating: 5)

      expect(review.reload.rating).to eq(5)
      expect(review.body).to eq("ok")
    end

    it "refuses someone else's review" do
      response = call(described_class, stranger, review_id: review.id, rating: 1)

      expect(payload(response)[:error]).to eq("forbidden")
      expect(review.reload.rating).to eq(3)
    end

    it "rejects a call that changes nothing" do
      response = call(described_class, author, review_id: review.id)

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::Reviews::DeleteReview do
    let!(:review) { create(:review, user: author, item: item) }

    it "destroys the author's own review" do
      call(described_class, author, review_id: review.id)

      expect(Review.exists?(review.id)).to be(false)
    end

    it "refuses someone else's review" do
      response = call(described_class, stranger, review_id: review.id)

      expect(payload(response)[:error]).to eq("forbidden")
      expect(Review.exists?(review.id)).to be(true)
    end

    # Deleting is irreversible; a client that surfaces annotations must be
    # able to prompt before this one runs.
    it "is annotated destructive" do
      expect(described_class.annotations_value.destructive_hint).to be(true)
    end
  end

  describe Tools::Reviews::ListReviews do
    # One review per (user, dish), so the hidden fixtures need their own
    # author or their own dish.
    let(:other_item) { create(:item, :published, restaurant: restaurant) }
    let!(:visible)   { create(:review, user: author, item: item, rating: 5, body: "great") }
    let!(:hidden_by_stranger) { create(:review, user: stranger, item: item, rating: 1, body: "spam") }
    let!(:hidden_of_mine)     { create(:review, user: author, item: other_item, rating: 1, body: "junk") }

    before do
      hidden_by_stranger.hide!(reason: "spam")
      hidden_of_mine.hide!(reason: "off_topic")
    end

    # A hidden review is hidden from the public feed. Leaking it through a
    # tool would make moderation cosmetic.
    it "omits hidden reviews from a dish's public feed" do
      response = call(described_class, nil, item_id: item.id)

      expect(payload(response)[:reviews].map { |r| r[:id] }).to eq([visible.id])
      expect(payload(response)[:total]).to eq(1)
    end

    # ...but the author is entitled to see their own, and to be told why.
    it "includes the caller's own hidden reviews with the reason" do
      response = call(described_class, author, mine: true)

      rows = payload(response)[:reviews]
      expect(rows.map { |r| r[:id] }).to contain_exactly(visible.id, hidden_of_mine.id)
      expect(rows.find { |r| r[:id] == hidden_of_mine.id }[:hidden_reason]).to eq("off_topic")
    end

    it "requires sign-in for mine: true" do
      response = call(described_class, nil, mine: true)

      expect(payload(response)[:error]).to eq("unauthorized")
    end

    it "needs one of item_id or mine" do
      response = call(described_class, author)

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "caps an absurd limit rather than dumping the table" do
      response = call(described_class, nil, item_id: item.id, limit: 5_000)

      expect(payload(response)[:reviews].size).to be <= described_class::MAX_LIMIT
    end
  end

  describe Tools::Reviews::ReportReview do
    let!(:review) { create(:review, user: author, item: item, body: "fine") }

    it "flags for moderation without hiding" do
      call(described_class, stranger, review_id: review.id)

      expect(review.reload.flagged_at).to be_present
      expect(review.hidden?).to be(false)
    end

    it "is idempotent — a second report keeps the original flag time" do
      call(described_class, stranger, review_id: review.id)
      first = review.reload.flagged_at
      call(described_class, stranger, review_id: review.id)

      expect(review.reload.flagged_at).to eq(first)
    end
  end
end
