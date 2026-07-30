require "rails_helper"

RSpec.describe Ingestion::ExistingItemMatcher do
  let(:restaurant) { create(:restaurant, :published) }
  let(:run)        { create(:ingestion_run, restaurant: restaurant, status: "resolving") }

  def staged(name, position: 0, **attrs)
    create(:ingestion_item, ingestion_run: run, name: name, position: position, **attrs)
  end

  def existing(name, status: "published", target: restaurant)
    create(:item, restaurant: target, name: name, status: status)
  end

  def matches
    described_class.call(run: run, items: run.ingestion_items.order(:position, :created_at).to_a)
  end

  describe "exact normalized matching" do
    it "matches a plural variant of an existing item at score 1.0" do
      target = existing("Carne Asada Taco")
      row    = staged("Carne Asada Tacos")

      expect(matches[row.id]).to eq(item_id: target.id, score: 1.0)
    end

    it "matches through punctuation and stopwords ('Mac & Cheese' = 'Mac and Cheese')" do
      target = existing("Mac and Cheese")
      row    = staged("Mac & Cheese")

      expect(matches[row.id]).to eq(item_id: target.id, score: 1.0)
    end

    it "matches regardless of token order ('Taco Carne Asada')" do
      target = existing("Carne Asada Taco")
      row    = staged("Taco Carne Asada")

      expect(matches[row.id]).to eq(item_id: target.id, score: 1.0)
    end

    it "matches across diacritics ('Jalapeño Poppers' = 'Jalapeno Poppers')" do
      target = existing("Jalapeno Poppers")
      row    = staged("Jalapeño Poppers")

      expect(matches[row.id]).to eq(item_id: target.id, score: 1.0)
    end
  end

  describe "similarity band with token-subset veto" do
    it "matches a spelling variant above the threshold" do
      target = existing("Margherita Pizza")
      row    = staged("Margarita Pizza")

      match = matches[row.id]
      expect(match[:item_id]).to eq(target.id)
      expect(match[:score]).to be_between(described_class::SIMILARITY_THRESHOLD, 1.0)
    end

    it "refuses a containment pair even though its similarity clears the threshold" do
      existing("Chicken Burrito Bowl")
      row = staged("Chicken Burrito")

      expect(matches[row.id]).to be_nil
    end

    it "refuses the reverse containment (staged name contains the existing one)" do
      existing("Cheeseburger")
      row = staged("Bacon Cheeseburger")

      expect(matches[row.id]).to be_nil
    end

    it "refuses different dishes below the threshold" do
      existing("Chicken Quesadilla")
      row = staged("Cheese Quesadilla")

      expect(matches[row.id]).to be_nil
    end

    # Pins the pg_trgm behavior the threshold + veto were calibrated
    # against. If Postgres' similarity() ever shifts these orderings the
    # constants must be re-derived, not patched around.
    it "calibration: the veto covers exactly the pairs no threshold can separate" do
      sim = lambda do |a, b|
        ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array(["SELECT similarity(?, ?)", a, b])
        ).to_f
      end

      threshold = described_class::SIMILARITY_THRESHOLD
      # Different dishes that SCORE ABOVE the threshold — only the subset
      # veto keeps them apart.
      expect(sim.call("chicken burrito", "chicken burrito bowl")).to be > threshold
      expect(sim.call("caesar salad", "side caesar salad")).to be > threshold
      # Same dish (spelling variant) that must clear the threshold.
      expect(sim.call("margherita pizza", "margarita pizza")).to be >= threshold
      # Different dishes that must stay below it.
      expect(sim.call("chicken quesadilla", "cheese quesadilla")).to be < threshold
      expect(sim.call("veggie burrito", "chicken burrito")).to be < threshold
    end
  end

  describe "candidate scope" do
    it "never matches another restaurant's items" do
      other = create(:restaurant, :published)
      existing("Carne Asada Taco", target: other)
      row = staged("Carne Asada Taco")

      expect(matches[row.id]).to be_nil
    end

    it "skips removed items" do
      existing("Carne Asada Taco", status: "removed")
      row = staged("Carne Asada Taco")

      expect(matches[row.id]).to be_nil
    end

    it "skips Items this run already promoted" do
      target = existing("Carne Asada Taco")
      staged("Carne Asada Taco", position: 0, item_id: target.id, decision: "accepted")
      second = staged("Carne Asada Taco", position: 1)

      expect(matches[second.id]).to be_nil
    end

    it "ignores staged rows that are already promoted" do
      target = existing("Pad Thai")
      row = staged("Pad Thai", item: create(:item, restaurant: restaurant, name: "Pad Thai"))

      expect(matches).not_to have_key(row.id)
      expect(target).to be_present
    end

    it "returns {} when the run has no restaurant" do
      orphan = create(:ingestion_run, restaurant: nil)
      create(:ingestion_item, ingestion_run: orphan, name: "Pad Thai")

      result = described_class.call(run: orphan, items: orphan.ingestion_items.to_a)
      expect(result).to eq({})
    end
  end

  describe "greedy one-to-one assignment" do
    it "lets only one of two identical staged rows claim the existing item (lowest position wins)" do
      target = existing("Carne Asada Taco")
      first  = staged("Carne Asada Taco", position: 0)
      second = staged("Carne Asada Taco", position: 1)

      result = matches
      expect(result[first.id]).to  eq(item_id: target.id, score: 1.0)
      expect(result[second.id]).to be_nil
    end

    it "prefers the exact match when an exact and a fuzzy staged row compete" do
      target = existing("Margherita Pizza")
      exact  = staged("Margherita Pizza", position: 1)
      fuzzy  = staged("Margarita Pizza",  position: 0)

      result = matches
      expect(result[exact.id]).to eq(item_id: target.id, score: 1.0)
      expect(result[fuzzy.id]).to be_nil
    end
  end
end
