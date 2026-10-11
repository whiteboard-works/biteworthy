require "rails_helper"

# Exhaustive table-driven spec for map_confidence. The rule is the authority;
# any test elsewhere that contradicts this one is wrong and must be updated.
RSpec.describe IngestionItem, "#map_confidence", type: :model do
  let(:item) { IngestionItem.new }

  # Matrix: (source, numeric, accept_cap) → expected confidence
  # source: nil (→"match"), "match", "derived", "ai"
  # numeric: nil, 0, 0.5, 0.79, 0.8, 0.93, 0.95, 1.0
  # accept_cap: "suggested" (community), "confirmed" (admin/owner)

  describe "community accept (accept_cap='suggested')" do
    let(:accept_cap) { "suggested" }

    context "source nil (treated as 'match')" do
      it "numeric nil → suggested" do
        expect(item.send(:map_confidence, nil, nil, accept_cap)).to eq("suggested")
      end

      it "numeric 0 → suggested" do
        expect(item.send(:map_confidence, 0, nil, accept_cap)).to eq("suggested")
      end

      it "numeric 0.93 → suggested" do
        expect(item.send(:map_confidence, 0.93, nil, accept_cap)).to eq("suggested")
      end

      it "numeric 0.95 → suggested (capped)" do
        expect(item.send(:map_confidence, 0.95, nil, accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested (capped)" do
        expect(item.send(:map_confidence, 1.0, nil, accept_cap)).to eq("suggested")
      end
    end

    context "source 'match'" do
      it "numeric nil → suggested" do
        expect(item.send(:map_confidence, nil, "match", accept_cap)).to eq("suggested")
      end

      it "numeric 0 → suggested" do
        expect(item.send(:map_confidence, 0, "match", accept_cap)).to eq("suggested")
      end

      it "numeric 0.93 → suggested" do
        expect(item.send(:map_confidence, 0.93, "match", accept_cap)).to eq("suggested")
      end

      it "numeric 0.95 → suggested (capped)" do
        expect(item.send(:map_confidence, 0.95, "match", accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested (capped)" do
        expect(item.send(:map_confidence, 1.0, "match", accept_cap)).to eq("suggested")
      end
    end

    context "source 'derived'" do
      it "numeric nil → suggested" do
        expect(item.send(:map_confidence, nil, "derived", accept_cap)).to eq("suggested")
      end

      it "numeric 0.8 → suggested" do
        expect(item.send(:map_confidence, 0.8, "derived", accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested" do
        expect(item.send(:map_confidence, 1.0, "derived", accept_cap)).to eq("suggested")
      end
    end

    context "source 'ai'" do
      it "numeric nil → inferred" do
        expect(item.send(:map_confidence, nil, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0 → inferred" do
        expect(item.send(:map_confidence, 0, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.5 → inferred" do
        expect(item.send(:map_confidence, 0.5, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.79 → inferred" do
        expect(item.send(:map_confidence, 0.79, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.8 → suggested" do
        expect(item.send(:map_confidence, 0.8, "ai", accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested" do
        expect(item.send(:map_confidence, 1.0, "ai", accept_cap)).to eq("suggested")
      end
    end
  end

  describe "admin/owner accept (accept_cap='confirmed')" do
    let(:accept_cap) { "confirmed" }

    context "source nil (treated as 'match')" do
      it "numeric nil → confirmed" do
        expect(item.send(:map_confidence, nil, nil, accept_cap)).to eq("confirmed")
      end

      it "numeric 0 → confirmed" do
        expect(item.send(:map_confidence, 0, nil, accept_cap)).to eq("confirmed")
      end

      it "numeric 0.93 → confirmed" do
        expect(item.send(:map_confidence, 0.93, nil, accept_cap)).to eq("confirmed")
      end

      it "numeric 1.0 → confirmed" do
        expect(item.send(:map_confidence, 1.0, nil, accept_cap)).to eq("confirmed")
      end
    end

    context "source 'match'" do
      it "numeric nil → confirmed" do
        expect(item.send(:map_confidence, nil, "match", accept_cap)).to eq("confirmed")
      end

      it "numeric 0 → confirmed" do
        expect(item.send(:map_confidence, 0, "match", accept_cap)).to eq("confirmed")
      end

      it "numeric 0.93 → confirmed" do
        expect(item.send(:map_confidence, 0.93, "match", accept_cap)).to eq("confirmed")
      end

      it "numeric 1.0 → confirmed" do
        expect(item.send(:map_confidence, 1.0, "match", accept_cap)).to eq("confirmed")
      end
    end

    context "source 'derived'" do
      it "numeric nil → suggested" do
        expect(item.send(:map_confidence, nil, "derived", accept_cap)).to eq("suggested")
      end

      it "numeric 0.8 → suggested" do
        expect(item.send(:map_confidence, 0.8, "derived", accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested" do
        expect(item.send(:map_confidence, 1.0, "derived", accept_cap)).to eq("suggested")
      end
    end

    context "source 'ai'" do
      it "numeric nil → inferred" do
        expect(item.send(:map_confidence, nil, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0 → inferred" do
        expect(item.send(:map_confidence, 0, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.5 → inferred" do
        expect(item.send(:map_confidence, 0.5, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.79 → inferred" do
        expect(item.send(:map_confidence, 0.79, "ai", accept_cap)).to eq("inferred")
      end

      it "numeric 0.8 → suggested" do
        expect(item.send(:map_confidence, 0.8, "ai", accept_cap)).to eq("suggested")
      end

      it "numeric 1.0 → suggested" do
        expect(item.send(:map_confidence, 1.0, "ai", accept_cap)).to eq("suggested")
      end
    end

    context "unknown source (fail closed)" do
      it "maps to inferred" do
        expect(item.send(:map_confidence, 1.0, "mystery", accept_cap)).to eq("inferred")
      end
    end

    context "source 'ingredient_derived' without from_source (fail closed)" do
      it "maps to inferred rather than treating the allergen as a menu-text match" do
        expect(item.send(:map_confidence, 1.0, "ingredient_derived", accept_cap)).to eq("inferred")
      end
    end
  end
end
