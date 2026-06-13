require "rails_helper"

# Phase 8.2 — SQL half of the SQL ↔ TS scoring parity contract.
#
# Loads the SAME fixture the filter-engine vitest suite asserts
# against (packages/filter-engine/fixtures/taste-parity.json),
# materializes its items in Postgres (real join rows so the
# denormalized arrays sync; real reviews so AVG(rating) is the real
# aggregate), and asserts TasteScoring's SQL produces the fixture's
# expected scores to 4 decimal places. If either implementation
# drifts, its half of this contract fails.
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
                    popularity: row["popularity"],
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
      create(:item, restaurant: restaurant, name: "Draft Special", popularity: 999) # status: draft
      other = create(:restaurant, :published)
      create(:item, :published, restaurant: other, name: "Elsewhere", popularity: 1)

      scores = described_class.scores_for(
        restaurant_id: restaurant.id,
        signals:       described_class::Signals.new(
          liked_ingredient_ids: [], liked_tag_ids: [fixture["tags"].keys.first],
          disliked_ingredient_ids: [], disliked_tag_ids: []
        )
      )
      expect(scores.keys).to match_array(items.map(&:id))
    end

    it "ignores hidden reviews in the rating term" do
      plate = items.find { |i| i.name == "Cheese Plate" } # unreviewed in fixture
      create(:review, item: plate, rating: 5, hidden_at: Time.current)

      scores = described_class.scores_for(
        restaurant_id: restaurant.id,
        signals:       described_class::Signals.new(
          liked_ingredient_ids: [], liked_tag_ids: [fixture["tags"].keys.first],
          disliked_ingredient_ids: [], disliked_tag_ids: []
        )
      )
      # Still no rating term: 0.5 * (50/100) only.
      expect(scores.fetch(plate.id)[:score]).to be_within(0.00005).of(0.25)
    end
  end
end
