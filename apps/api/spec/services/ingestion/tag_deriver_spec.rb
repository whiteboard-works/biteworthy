require "rails_helper"

RSpec.describe Ingestion::TagDeriver do
  def ing(slug, path, confidence: 0.95, source: "match")
    { slug:, path:, confidence:, source: }
  end

  def derive(text: "", section: nil, ingredients: [])
    described_class.derive(
      segments:             Ingestion::MenuText.segments(text),
      section_segments:     Ingestion::MenuText.segments(section),
      resolved_ingredients: ingredients
    )
  end

  def tag_slugs(tags) = tags.map { |t| t[:slug] }

  describe "allergen (derived from ingredient ancestry)" do
    it "maps subtree membership to contains-* tags" do
      tags = derive(ingredients: [
        ing("dairy-goat-cheese", "dairy.goat_cheese"),
        ing("grain-wheat-bread-ciabatta", "grain.wheat.bread.ciabatta"),
        ing("legume-peanuts-peanut-butter", "legume.peanuts.peanut_butter"),
      ])
      expect(tag_slugs(tags)).to contain_exactly(
        "contains-dairy", "contains-gluten", "contains-peanut"
      )
    end

    it "does not flag gluten for non-gluten grains" do
      tags = derive(ingredients: [ing("grain-rice", "grain.rice")])
      expect(tag_slugs(tags)).not_to include("contains-gluten")
    end

    it "applies cross-root slug exceptions (oyster sauce, coconut)" do
      tags = derive(ingredients: [
        ing("condiment-oyster-sauce", "condiment.oyster_sauce"),
        ing("fruit-coconut", "fruit.coconut"),
      ])
      expect(tag_slugs(tags)).to include("contains-shellfish", "contains-tree-nut")
    end

    it "is nil-safe when ingredients or paths are missing" do
      expect { derive(ingredients: nil) }.not_to raise_error
      expect(derive(ingredients: nil)).to eq([])
      expect { derive(ingredients: [ { slug: nil, path: nil } ]) }.not_to raise_error
    end

    it "carries the ingredient's confidence and marks provenance" do
      derived = derive(ingredients: [ing("egg", "egg", confidence: 0.8)])
      ai      = derive(ingredients: [ing("egg", "egg", confidence: 0.7, source: "ai")])
      expect(derived.first).to include(
        slug: "contains-egg", confidence: 0.8,
        source: "ingredient_derived", from_source: "match"
      )
      expect(ai.first).to include(
        slug: "contains-egg", confidence: 0.7,
        source: "ingredient_derived", from_source: "ai"
      )
    end

    it "keeps the best confidence when two ingredients derive the same tag" do
      tags = derive(ingredients: [
        ing("dairy-cheese", "dairy.cheese", confidence: 0.95),
        ing("dairy-butter", "dairy.butter", confidence: 1.0),
      ])
      expect(tags).to contain_exactly(include(slug: "contains-dairy", confidence: 1.0))
    end
  end

  describe "diet (explicit claims + ancestry veto)" do
    it "matches explicit claims, including multi-word ones" do
      tags = derive(text: "Vegan bowl, gluten free")
      expect(tag_slugs(tags)).to include("vegan", "gluten-free")
    end

    it "suppresses vegan/vegetarian when an animal ingredient resolved" do
      tags = derive(text: "vegan option available", ingredients: [ing("meat-beef", "meat.beef")])
      expect(tag_slugs(tags)).not_to include("vegan", "vegetarian")
    end

    it "suppresses vegan (but not vegetarian) on dairy/egg" do
      tags = derive(
        text: "vegan or vegetarian",
        ingredients: [ing("dairy-cheese", "dairy.cheese")]
      )
      expect(tag_slugs(tags)).to include("vegetarian")
      expect(tag_slugs(tags)).not_to include("vegan")
    end

    it "never infers a diet from ingredient absence" do
      expect(derive(text: "Garden salad")).to be_empty
    end

    it "suppresses gluten-free when a gluten ingredient resolved" do
      tags = derive(
        text: "crispy chicken sandwich - gluten free option",
        ingredients: [ing("grain-wheat-brioche", "grain.wheat.bread.brioche")]
      )
      expect(tag_slugs(tags)).not_to include("gluten-free")
      expect(tag_slugs(tags)).to include("contains-gluten")
    end

    it "suppresses dairy-free and nut-free on contradicting ingredients (incl. slug exceptions)" do
      tags = derive(
        text: "dairy free, nut free",
        ingredients: [
          ing("dairy-cheese", "dairy.cheese"),
          ing("fruit-coconut", "fruit.coconut"), # tree nut via SLUG_TAGS
        ]
      )
      expect(tag_slugs(tags)).not_to include("dairy-free", "nut-free")
    end

    it "keeps a gluten-free claim when nothing contradicts it" do
      tags = derive(text: "gluten free bowl", ingredients: [ing("grain-rice", "grain.rice")])
      expect(tag_slugs(tags)).to include("gluten-free")
    end
  end

  describe "prep / flavor keywords" do
    it "matches prep and flavor tables" do
      tags = derive(text: "Spicy fried chicken, house smoked")
      expect(tag_slugs(tags)).to include("fried", "smoked", "spicy")
    end

    it "requires whole-phrase hits, not substrings" do
      # "unfried" normalizes to its own token; must not hit "fried".
      expect(tag_slugs(derive(text: "unfried greens"))).not_to include("fried")
    end
  end

  describe "cuisine (weak keyword pass incl. section)" do
    it "matches cuisine words in the section name" do
      tags = derive(text: "Al Pastor", section: "Mexican Classics")
      expect(tag_slugs(tags)).to include("mexican")
    end

    it "knows the cuisines added for Jev's sake, including the two-word ones" do
      expect(tag_slugs(derive(text: "Sherpa Stew", section: "Nepali Specialties"))).to include("nepali-tibetan")
      expect(tag_slugs(derive(text: "Shawarma Plate", section: "Middle Eastern"))).to include("middle-eastern")
      slugs = tag_slugs(derive(text: "Arepas", section: "Latin American Plates"))
      # The longer phrase wins outright: not also `american`, which would
      # put two sibling cuisines on one dish and double-count its taste.
      expect(slugs).to include("latin-american")
      expect(slugs).not_to include("american")
      expect(tag_slugs(derive(text: "Burger", section: "American Classics"))).to include("american")
      # Only the shadowed occurrence is dropped; a standalone one still counts.
      expect(tag_slugs(derive(text: "American Burger", section: "Latin American Plates")))
        .to include("american", "latin-american")
    end

    # The word is on the menu, the cuisine is not: this pass fires at
    # 0.9 with nothing to veto it, so a modifier word must never be a
    # keyword, however real the cuisine. Those dishes are Jev's call.
    it "leaves cuisine words that are also dish modifiers alone" do
      [
        [ "Spanish Rice", "Southern Colorado Favorites", %w[spanish southern latin-american] ],
        [ "French Fries", "Sides", %w[french] ],
        [ "Greek Yogurt Parfait", "Breakfast", %w[greek] ],
        [ "German Chocolate Cake", "Desserts", %w[german] ],
        [ "BBQ Chicken Pizza", "Pizzas", %w[bbq] ],
        [ "Cajun Fries", "Sides", %w[cajun-creole] ],
        [ "Himalayan Salt Margarita", "Cocktails", %w[nepali-tibetan] ],
        [ "Texas Toast", "Sides", %w[tex-mex] ]
      ].each do |text, section, slugs|
        expect(tag_slugs(derive(text: text, section: section)) & slugs).to be_empty, text
      end
    end
  end

  describe "per-family isolation" do
    it "one strategy raising doesn't block the others" do
      allow(Ingestion::TagDeriver::Diet).to receive(:call).and_raise("boom")
      allow(Rails.logger).to receive(:error)
      tags = derive(text: "grilled halibut", ingredients: [ing("fish-halibut", "fish.halibut")])
      expect(tag_slugs(tags)).to include("grilled", "contains-fish")
      expect(Rails.logger).to have_received(:error).with(/diet strategy failed/)
    end
  end
end
