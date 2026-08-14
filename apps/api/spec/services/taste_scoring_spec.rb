require "rails_helper"

# Phase 8.2 — the regression fixture for the scoring SQL.
#
# Loads packages/filter-engine/fixtures/taste-parity.json, materializes
# its items in Postgres (real join rows so the denormalized arrays sync;
# real reviews so AVG(rating) is the real aggregate), and asserts
# TasteScoring's SQL produces the fixture's expected scores to 4 decimal
# places. Hand-written expectations, computed independently of the query
# — which is what makes them worth asserting against.
#
# The fixture used to have a TS twin asserting the same numbers against a
# `scoreItem` mirror; that mirror had no callers and was deleted, so this
# spec is now its only consumer. The file stays here rather than moving
# into spec/fixtures because it is data, not Ruby, and moving a shipped
# fixture buys nothing.
RSpec.describe TasteScoring do
  fixture_path = Rails.root.join("../../packages/filter-engine/fixtures/taste-parity.json")
  fixture      = JSON.parse(File.read(fixture_path))

  let(:restaurant) { create(:restaurant, :published) }

  let!(:taxonomy) do
    fixture["tags"].each do |id, name|
      create(:tag, id: id, name: name, slug: name.parameterize)
    end
    fixture["ingredients"].each do |id, name|
      create(:ingredient, id: id, name: name, slug: name.parameterize)
    end
  end

  let!(:items) do
    fixture["items"].map do |row|
      item = create(:item, :published,
                    id:         row["id"],
                    restaurant: restaurant,
                    name:       row["name"],
                    ingredients: Ingredient.where(id: row["ingredient_ids"]),
                    tag_list:    Tag.where(id: row["tag_ids"]))
      row["review_ratings"].each { |rating| create(:review, item: item, rating: rating) }
      item
    end
  end

  fixture["profiles"].each do |profile|
    context "profile: #{profile['key']}" do
      let(:signals) do
        described_class::Signals.new(
          liked_ingredient_ids:    profile["liked_ingredient_ids"]    - profile["avoid_ingredient_ids"],
          liked_tag_ids:           profile["liked_tag_ids"]           - profile["avoid_tag_ids"],
          disliked_ingredient_ids: profile["disliked_ingredient_ids"] - profile["avoid_ingredient_ids"],
          disliked_tag_ids:        profile["disliked_tag_ids"]        - profile["avoid_tag_ids"]
        )
      end

      fixture["items"].each do |row|
        expected = row["expected"][profile["key"]]
        next if expected.nil?

        it "scores \"#{row['name']}\" = #{expected['score']}" do
          scores = described_class.scores_for(restaurant_id: restaurant.id, signals: signals)
          result = scores.fetch(row["id"])

          expect(result[:score]).to be_within(0.00005).of(expected["score"])
          expect(result[:matched_liked_tag_ids]).to        eq(expected["matched_liked_tag_ids"])
          expect(result[:matched_liked_ingredient_ids]).to eq(expected["matched_liked_ingredient_ids"])
        end
      end
    end
  end

  describe "scoping" do
    it "scores only published items at the given restaurant" do
      create(:item, restaurant: restaurant, name: "Draft Special") # status: draft
      other = create(:restaurant, :published)
      create(:item, :published, restaurant: other, name: "Elsewhere")

      scores = described_class.scores_for(
        restaurant_id: restaurant.id,
        signals:       described_class::Signals.new(
          liked_ingredient_ids: [], liked_tag_ids: [fixture["tags"].keys.first],
          disliked_ingredient_ids: [], disliked_tag_ids: []
        )
      )
      expect(scores.keys).to match_array(items.map(&:id))
    end

    # Asserted as a comparison rather than against a number. The plate
    # matches no signal and has no visible review, so its score is 0.0 —
    # and 0.0 is also what "the scorer never ran" looks like, so a bare
    # `eq(0.0)` would pass for the wrong reason. Pinning the hidden review
    # as a no-op AND the same review as a real move proves the rating term
    # both exists and skips what it should.
    it "ignores hidden reviews in the rating term" do
      plate = items.find { |i| i.name == "Cheese Plate" } # unreviewed in fixture
      score = lambda do
        described_class.scores_for(
          restaurant_id: restaurant.id,
          signals:       described_class::Signals.new(
            liked_ingredient_ids: [], liked_tag_ids: [fixture["tags"].keys.first],
            disliked_ingredient_ids: [], disliked_tag_ids: []
          )
        ).fetch(plate.id)[:score]
      end

      baseline = score.call
      review   = create(:review, item: plate, rating: 5, hidden_at: Time.current)
      expect(score.call).to be_within(0.00005).of(baseline)

      review.update!(hidden_at: nil)
      # 0.5 * (5 - 3) / 2
      expect(score.call).to be_within(0.00005).of(baseline + 0.5)
    end
  end
end
