require "rails_helper"

# End-to-end verification that the expanded Celiac/gluten-free coverage catches
# common gluten sources in real dish names. Tests flow through the matcher/resolver,
# not by attaching ingredients directly — this is what catches false negatives where
# the taxonomy exists but the name doesn't match.
RSpec.describe "Celiac/gluten-free filter coverage" do
  let(:restaurant) { create(:restaurant, :published) }
  let(:celiac_profile) { DietaryProfile.find_by!(slug: "celiac") }
  let(:user) { create(:user) }

  before do
    # Load all seed ingredients so the matcher has the full catalog
    Ingredient.delete_all
    YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")).each do |attrs|
      Ingredient.create!(attrs.symbolize_keys)
    end

    # Set user to celiac preset
    user.profile.update!(
      primary_dietary_profile_id: celiac_profile.id,
      avoid_ingredient_ids: celiac_profile.dietary_profile_ingredients
                                          .where(rule: "avoid")
                                          .pluck(:ingredient_id)
    )
  end

  def filter_for(user, strictness: "balanced")
    Menus::Filter.build(user: user, strictness: strictness)
  end

  def create_item_from_name(name, description = nil)
    # Use the deterministic resolver to process the dish name/description
    # the way ingestion does, then create an Item with those resolved ingredients
    stub_item = Struct.new(:id, :name, :description, :section_name).new(
      SecureRandom.uuid, name, description, "Entrees"
    )

    matcher = Ingestion::IngredientMatcher.new(
      Ingredient.pluck(:slug, :name, :path, :aliases)
    )
    result = Ingestion::DeterministicResolver.call([ stub_item ], matcher: matcher).first

    item = create(:item, :published, restaurant: restaurant, name: name, description: description)

    # Create the ingredient associations from the resolved payload
    result.ingredients.each do |ing|
      ingredient = Ingredient.find_by!(slug: ing["slug"])
      create(:item_ingredient,
        item: item,
        ingredient: ingredient,
        confidence: ing["confidence"] == 1.0 ? "confirmed" : "suggested",
        source: "human"
      )
    end

    item
  end

  def hidden_by_celiac?(item)
    filter = filter_for(user)
    reasons = filter.reasons_for(item.reload, Menus::Labels.for_filter([ item ], filter))
    reasons.any?
  end

  describe "soy sauce, shoyu, teriyaki" do
    it "hides dishes with soy sauce (contains wheat)" do
      item = create_item_from_name("Chicken Teriyaki", "grilled chicken with teriyaki sauce")
      expect(hidden_by_celiac?(item)).to be(true), "Teriyaki should be hidden for Celiac users"
    end

    it "hides dishes with shoyu" do
      item = create_item_from_name("Shoyu Ramen", "ramen noodles in shoyu broth")
      expect(hidden_by_celiac?(item)).to be(true), "Shoyu should be hidden for Celiac users"
    end

    it "hides soy sauce unless marked gluten-free" do
      item = create_item_from_name("Stir Fry", "vegetables with soy sauce")
      expect(hidden_by_celiac?(item)).to be(true), "Soy sauce should be hidden for Celiac users"
    end
  end

  describe "malt and malt vinegar" do
    it "hides dishes with malt vinegar" do
      item = create_item_from_name("Fish and Chips", "battered fish with malt vinegar")
      expect(hidden_by_celiac?(item)).to be(true), "Malt vinegar should be hidden for Celiac users"
    end

    it "hides dishes containing malt" do
      item = create_item_from_name("Milkshake", "ice cream with malt")
      expect(hidden_by_celiac?(item)).to be(true), "Malt should be hidden for Celiac users"
    end
  end

  describe "gravy" do
    it "hides dishes with gravy (typically wheat-thickened)" do
      item = create_item_from_name("Biscuits and Gravy", "biscuits with brown gravy")
      expect(hidden_by_celiac?(item)).to be(true), "Gravy should be hidden for Celiac users"
    end

    it "hides plain gravy unless marked gluten-free" do
      item = create_item_from_name("Pot Roast", "beef with gravy")
      expect(hidden_by_celiac?(item)).to be(true), "Gravy should be hidden for Celiac users"
    end
  end

  describe "beer types: stout, lager, porter, IPA, pilsner" do
    it "hides dishes with stout" do
      item = create_item_from_name("Beef Stew", "slow-cooked beef in stout")
      expect(hidden_by_celiac?(item)).to be(true), "Stout should be hidden for Celiac users"
    end

    it "hides dishes with lager" do
      item = create_item_from_name("Beer Brats", "bratwurst cooked in lager")
      expect(hidden_by_celiac?(item)).to be(true), "Lager should be hidden for Celiac users"
    end

    it "hides dishes with porter" do
      item = create_item_from_name("Porter BBQ Ribs", "ribs with porter BBQ sauce")
      expect(hidden_by_celiac?(item)).to be(true), "Porter should be hidden for Celiac users"
    end

    it "hides dishes with IPA" do
      item = create_item_from_name("IPA Onion Rings", "onion rings with IPA batter")
      expect(hidden_by_celiac?(item)).to be(true), "IPA should be hidden for Celiac users"
    end

    it "hides dishes with pilsner" do
      item = create_item_from_name("Pilsner Cheese Soup", "cheese soup with pilsner")
      expect(hidden_by_celiac?(item)).to be(true), "Pilsner should be hidden for Celiac users"
    end
  end

  describe "battered, breaded, crusted, tempura, panko" do
    it "hides battered dishes" do
      item = create_item_from_name("Fish and Chips", "battered cod")
      expect(hidden_by_celiac?(item)).to be(true), "Battered should be hidden for Celiac users"
    end

    it "hides breaded dishes" do
      item = create_item_from_name("Chicken Tenders", "breaded chicken strips")
      expect(hidden_by_celiac?(item)).to be(true), "Breaded should be hidden for Celiac users"
    end

    it "hides tempura dishes" do
      item = create_item_from_name("Tempura Vegetables", "vegetables in tempura batter")
      expect(hidden_by_celiac?(item)).to be(true), "Tempura should be hidden for Celiac users"
    end

    it "hides panko-crusted dishes" do
      item = create_item_from_name("Panko Chicken", "chicken crusted with panko")
      expect(hidden_by_celiac?(item)).to be(true), "Panko should be hidden for Celiac users"
    end
  end

  describe "Indian breads: roti, chapati, paratha, puri, naan" do
    it "hides dishes with roti" do
      item = create_item_from_name("Curry with Roti", "chicken curry served with roti")
      expect(hidden_by_celiac?(item)).to be(true), "Roti should be hidden for Celiac users"
    end

    it "hides dishes with chapati" do
      item = create_item_from_name("Dal with Chapati", "lentil dal with chapati")
      expect(hidden_by_celiac?(item)).to be(true), "Chapati should be hidden for Celiac users"
    end

    it "hides dishes with paratha" do
      item = create_item_from_name("Aloo Paratha", "potato-stuffed paratha")
      expect(hidden_by_celiac?(item)).to be(true), "Paratha should be hidden for Celiac users"
    end

    it "hides dishes with puri" do
      item = create_item_from_name("Puri Bhaji", "puri with potato curry")
      expect(hidden_by_celiac?(item)).to be(true), "Puri should be hidden for Celiac users"
    end

    it "hides dishes with naan" do
      item = create_item_from_name("Garlic Naan", "naan bread with garlic")
      expect(hidden_by_celiac?(item)).to be(true), "Naan should be hidden for Celiac users"
    end

    it "hides Himalayan momos (wheat dumpling)" do
      item = create_item_from_name("Chicken Momo", "steamed momos with chicken")
      expect(hidden_by_celiac?(item)).to be(true), "Momo should be hidden for Celiac users"
    end
  end

  describe "dumplings, wrappers: empanada, egg roll, spring roll, wonton, dumpling, schnitzel, katsu, croquette" do
    it "hides empanadas" do
      item = create_item_from_name("Beef Empanada", "pastry filled with beef")
      expect(hidden_by_celiac?(item)).to be(true), "Empanada should be hidden for Celiac users"
    end

    it "hides egg rolls" do
      item = create_item_from_name("Pork Egg Roll", "fried egg roll with pork")
      expect(hidden_by_celiac?(item)).to be(true), "Egg roll should be hidden for Celiac users"
    end

    it "hides spring rolls (wheat wrapper)" do
      item = create_item_from_name("Fried Spring Rolls", "crispy spring rolls")
      expect(hidden_by_celiac?(item)).to be(true), "Spring roll should be hidden for Celiac users"
    end

    it "hides wontons" do
      item = create_item_from_name("Wonton Soup", "soup with wontons")
      expect(hidden_by_celiac?(item)).to be(true), "Wonton should be hidden for Celiac users"
    end

    it "hides generic dumplings" do
      item = create_item_from_name("Pork Dumplings", "steamed dumplings")
      expect(hidden_by_celiac?(item)).to be(true), "Dumpling should be hidden for Celiac users"
    end

    it "hides schnitzel" do
      item = create_item_from_name("Wiener Schnitzel", "breaded veal cutlet")
      expect(hidden_by_celiac?(item)).to be(true), "Schnitzel should be hidden for Celiac users"
    end

    it "hides katsu" do
      item = create_item_from_name("Chicken Katsu", "breaded chicken cutlet")
      expect(hidden_by_celiac?(item)).to be(true), "Katsu should be hidden for Celiac users"
    end

    it "hides croquettes" do
      item = create_item_from_name("Potato Croquettes", "fried potato croquettes")
      expect(hidden_by_celiac?(item)).to be(true), "Croquette should be hidden for Celiac users"
    end
  end

  describe "wheat grains: seitan, couscous, bulgur, farro, orzo" do
    it "hides seitan" do
      item = create_item_from_name("Seitan Stir Fry", "stir-fried seitan")
      expect(hidden_by_celiac?(item)).to be(true), "Seitan should be hidden for Celiac users"
    end

    it "hides couscous" do
      item = create_item_from_name("Moroccan Couscous", "couscous with vegetables")
      expect(hidden_by_celiac?(item)).to be(true), "Couscous should be hidden for Celiac users"
    end

    it "hides bulgur" do
      item = create_item_from_name("Tabbouleh", "bulgur salad with herbs")
      expect(hidden_by_celiac?(item)).to be(true), "Bulgur should be hidden for Celiac users"
    end

    it "hides farro" do
      item = create_item_from_name("Farro Salad", "farro with roasted vegetables")
      expect(hidden_by_celiac?(item)).to be(true), "Farro should be hidden for Celiac users"
    end

    it "hides orzo" do
      item = create_item_from_name("Orzo Pasta", "orzo with tomatoes")
      expect(hidden_by_celiac?(item)).to be(true), "Orzo should be hidden for Celiac users"
    end
  end

  describe "wheat noodles: udon, ramen, lo mein, chow mein" do
    it "hides udon" do
      item = create_item_from_name("Udon Noodle Soup", "thick udon noodles")
      expect(hidden_by_celiac?(item)).to be(true), "Udon should be hidden for Celiac users"
    end

    it "hides ramen" do
      item = create_item_from_name("Miso Ramen", "ramen noodles in miso broth")
      expect(hidden_by_celiac?(item)).to be(true), "Ramen should be hidden for Celiac users"
    end

    it "hides lo mein" do
      item = create_item_from_name("Vegetable Lo Mein", "lo mein with vegetables")
      expect(hidden_by_celiac?(item)).to be(true), "Lo mein should be hidden for Celiac users"
    end

    it "hides chow mein" do
      item = create_item_from_name("Chicken Chow Mein", "chow mein with chicken")
      expect(hidden_by_celiac?(item)).to be(true), "Chow mein should be hidden for Celiac users"
    end
  end

  describe "PR 766 keywords: Hotcakes, Samosa, Biscuits, Chile Relleno, Gulab Jamun" do
    it "hides hotcakes/pancakes" do
      item = create_item_from_name("Buttermilk Hotcakes", "fluffy hotcakes")
      expect(hidden_by_celiac?(item)).to be(true), "Hotcakes should be hidden for Celiac users"
    end

    it "hides samosas" do
      item = create_item_from_name("Vegetable Samosa", "fried samosa with potatoes")
      expect(hidden_by_celiac?(item)).to be(true), "Samosa should be hidden for Celiac users"
    end

    it "hides biscuits and gravy" do
      item = create_item_from_name("Biscuits and Gravy", "biscuits with sausage gravy")
      expect(hidden_by_celiac?(item)).to be(true), "Biscuits should be hidden for Celiac users"
    end

    it "hides chile relleno" do
      item = create_item_from_name("Chile Relleno", "stuffed chile relleno")
      expect(hidden_by_celiac?(item)).to be(true), "Chile relleno should be hidden for Celiac users"
    end

    it "hides gulab jamun" do
      item = create_item_from_name("Gulab Jamun", "sweet gulab jamun dessert")
      expect(hidden_by_celiac?(item)).to be(true), "Gulab jamun should be hidden for Celiac users"
    end
  end

  describe "negative cases: should NOT be hidden" do
    it "shows corn tortilla tacos" do
      item = create_item_from_name("Corn Tortilla Tacos", "tacos with corn tortillas")
      expect(hidden_by_celiac?(item)).to be(false), "Corn tortillas should be safe for Celiac users"
    end

    it "shows rice noodle pho" do
      item = create_item_from_name("Rice Noodle Pho", "pho with rice noodles")
      expect(hidden_by_celiac?(item)).to be(false), "Rice noodles should be safe for Celiac users"
    end

    it "shows tamari-glazed dishes when explicitly marked" do
      item = create_item_from_name("Tamari Glazed Salmon", "salmon with tamari glaze")
      expect(hidden_by_celiac?(item)).to be(false), "Tamari should be safe for Celiac users"
    end

    it "shows gluten-free pancakes when marked" do
      item = create_item_from_name("GF Pancakes", "gluten-free pancakes")
      expect(hidden_by_celiac?(item)).to be(false), "GF pancakes should be safe for Celiac users"
    end

    it "shows rice paper spring rolls" do
      item = create_item_from_name("Fresh Spring Rolls", "rice paper spring rolls")
      expect(hidden_by_celiac?(item)).to be(false), "Rice paper should be safe for Celiac users"
    end

    it "shows dishes with rice vinegar" do
      item = create_item_from_name("Cucumber Salad", "cucumbers with rice vinegar")
      expect(hidden_by_celiac?(item)).to be(false), "Rice vinegar should be safe for Celiac users"
    end
  end
end
