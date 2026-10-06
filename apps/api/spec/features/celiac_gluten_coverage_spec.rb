require "rails_helper"

# Real dish names through IngredientMatcher + DeterministicResolver, then
# the Celiac preset. Attaching ingredients by hand would not catch a
# catalog row that exists but never matches the words on a menu.
RSpec.describe "Celiac filter over real dish names" do
  let(:restaurant) { create(:restaurant, :published) }

  def load_catalog!
    YAML.load_file(Rails.root.join("db/seeds/ingredients.yml")).each do |attrs|
      Ingredient.find_or_initialize_by(slug: attrs["slug"]).tap do |ing|
        ing.assign_attributes(attrs.symbolize_keys)
        ing.save!
      end
    end
  end

  def seed_celiac_preset!
    row = YAML.load_file(Rails.root.join("db/seeds/dietary_profiles.yml"))
              .find { |preset| preset["slug"] == "celiac" }
    slugs = row.delete("avoid_ingredient_slugs") || []
    paths = row.delete("avoid_ingredient_paths") || []
    row.delete("avoid_tag_slugs")
    row.delete("avoid_tag_paths")

    profile = DietaryProfile.find_or_initialize_by(slug: "celiac")
    profile.assign_attributes(row.slice("name", "description"))
    profile.save!

    ingredient_ids = (
      Ingredient.where(slug: slugs).pluck(:id) +
      Ingredient.where("path <@ ARRAY[?]::ltree[]", paths).pluck(:id)
    ).uniq

    ingredient_ids.each do |ingredient_id|
      DietaryProfileIngredient.find_or_create_by!(
        dietary_profile: profile, ingredient_id: ingredient_id, rule: "avoid"
      )
    end
  end

  def resolve_item(name, description)
    stub = Struct.new(:id, :name, :description, :section_name)
                 .new(SecureRandom.uuid, name, description, "Entrees")
    matcher = Ingestion::IngredientMatcher.new(
      Ingredient.pluck(:slug, :name, :path, :aliases)
    )
    Ingestion::DeterministicResolver.call([ stub ], matcher: matcher).first
  end

  def publish_resolved(name, description)
    result = resolve_item(name, description)
    item = create(:item, :published, :confirmed, restaurant: restaurant,
                                                 name: name, description: description.to_s)
    result.ingredients.each do |row|
      ingredient = Ingredient.find_by!(slug: row["slug"])
      ItemIngredient.find_or_create_by!(item: item, ingredient: ingredient) do |join|
        join.confidence = "confirmed"
        join.source = row["source"] == "derived" ? "derived" : "human"
      end
    end
    item.reload
  end

  def hidden_by_celiac?(item)
    filter = Menus::Filter.build(preset_slug: "celiac")
    reasons = filter.reasons_for(item, Menus::Labels.for_filter([ item ], filter))
    reasons.any?
  end

  # name, description, hidden?, why the assertion exists
  DISHES = [
    [ "Chicken Teriyaki", "grilled chicken with teriyaki sauce", true, "teriyaki carries wheat" ],
    [ "Shoyu Ramen", "ramen noodles in shoyu broth", true, "shoyu is soy sauce" ],
    [ "Vegetable Stir Fry", "vegetables tossed in soy sauce", true, "soy sauce carries wheat" ],
    [ "Fish and Chips", "battered cod with malt vinegar", true, "batter + malt vinegar" ],
    [ "Malted Milkshake", "ice cream with malt", true, "malt is barley" ],
    [ "Biscuits and Gravy", "biscuits with brown gravy", true, "biscuit + gravy" ],
    [ "Pot Roast", "beef with gravy", true, "plain gravy is wheat-thickened" ],
    [ "Beef Stew", "slow-cooked beef in stout", true, "stout is beer" ],
    [ "Beer Brats", "bratwurst cooked in lager", true, "lager is beer" ],
    [ "Porter BBQ Ribs", "ribs with porter barbecue sauce", true, "porter is beer" ],
    [ "IPA Onion Rings", "onion rings in IPA batter", true, "IPA is beer" ],
    [ "Pilsner Cheese Soup", "cheese soup with pilsner", true, "pilsner is beer" ],
    [ "Chicken Tenders", "breaded chicken strips", true, "breaded" ],
    [ "Tempura Vegetables", "vegetables in tempura batter", true, "tempura" ],
    [ "Panko Chicken", "chicken crusted with panko", true, "panko / crusted" ],
    [ "Curry with Roti", "chicken curry served with roti", true, "roti" ],
    [ "Dal with Chapati", "lentil dal with chapati", true, "chapati" ],
    [ "Aloo Paratha", "potato-stuffed paratha", true, "paratha" ],
    [ "Puri Bhaji", "puri with potato curry", true, "puri" ],
    [ "Garlic Naan", "naan bread with garlic", true, "naan" ],
    [ "Chicken Momo", "steamed momos with chicken", true, "Himalayan dumpling wrapper" ],
    [ "Beef Empanada", "pastry filled with beef", true, "empanada" ],
    [ "Pork Egg Roll", "fried egg roll with pork", true, "egg roll" ],
    [ "Fried Spring Rolls", "crispy spring rolls", true, "wheat spring roll" ],
    [ "Wonton Soup", "soup with wontons", true, "wonton" ],
    [ "Pork Dumplings", "steamed dumplings", true, "dumpling" ],
    [ "Wiener Schnitzel", "breaded veal cutlet", true, "schnitzel" ],
    [ "Chicken Katsu", "breaded chicken cutlet", true, "katsu" ],
    [ "Potato Croquettes", "fried potato croquettes", true, "croquette" ],
    [ "Seitan Stir Fry", "stir-fried seitan", true, "seitan is wheat gluten" ],
    [ "Moroccan Couscous", "couscous with vegetables", true, "couscous" ],
    [ "Tabbouleh", "bulgur salad with herbs", true, "bulgur" ],
    [ "Farro Salad", "farro with roasted vegetables", true, "farro" ],
    [ "Orzo Pasta", "orzo with tomatoes", true, "orzo" ],
    [ "Udon Noodle Soup", "thick udon noodles", true, "udon" ],
    [ "Miso Ramen", "ramen noodles in miso broth", true, "ramen" ],
    [ "Vegetable Lo Mein", "lo mein with vegetables", true, "lo mein" ],
    [ "Chicken Chow Mein", "chow mein with chicken", true, "chow mein" ],
    [ "Buttermilk Hotcakes", "fluffy hotcakes", true, "PR 766 hotcake alias" ],
    [ "Vegetable Samosa", "fried samosa with potatoes", true, "PR 766 samosa keyword" ],
    [ "Chile Relleno", "stuffed chile relleno", true, "PR 766 relleno keyword" ],
    [ "Gulab Jamun", "sweet gulab jamun dessert", true, "PR 766 gulab jamun keyword" ],
    [ "Corn Tortilla Tacos", "tacos with corn tortillas", false, "corn tortilla is not wheat" ],
    [ "Rice Noodle Pho", "pho with rice noodles", false, "rice noodles are not wheat" ],
    [ "Tamari Glazed Salmon", "salmon with tamari glaze", false, "tamari stays gluten-free" ],
    [ "GF Pancakes", "served with maple syrup", false, "explicit GF claim on the name" ]
  ].freeze

  it "hides hidden-gluten dishes and shows the safe negatives" do
    load_catalog!
    seed_celiac_preset!

    failures = DISHES.filter_map do |name, description, expect_hidden, reason|
      item = publish_resolved(name, description)
      hidden = hidden_by_celiac?(item)
      next if hidden == expect_hidden

      slugs = item.item_ingredients.map { |join| join.ingredient.slug }.sort
      "#{name}: expected hidden=#{expect_hidden} (#{reason}) got #{hidden} slugs=#{slugs}"
    end

    expect(failures).to eq([])
  end
end
