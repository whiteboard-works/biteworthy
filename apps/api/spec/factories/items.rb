FactoryBot.define do
  # Real-ish menu items pulled from the 2020 seed data + a few
  # invented ones that exercise the dietary filter (cheese pizza =
  # contains dairy; carne asada = contains beef, no dairy; etc.).
  ITEM_SAMPLES = [
    "Carne Asada Taco", "Pollo Taco", "Veggie Burrito", "Bean & Cheese Burrito",
    "Cheese Pizza", "Pepperoni Pizza", "Margherita Pizza", "Mushroom Pizza",
    "Pad Thai", "Green Curry", "Tom Kha Soup", "Drunken Noodles",
    "Fish & Chips", "Caesar Salad", "House Salad", "Tomato Bisque",
    "Steak Frites", "Salmon Bowl", "Chicken Caesar Wrap", "Avocado Toast",
    "Acai Bowl", "Yogurt Parfait", "Cinnamon Roll", "Iced Latte"
  ].freeze

  factory :menu do
    restaurant
    name { "Main" }
    position { 0 }
  end

  factory :menu_section do
    menu
    sequence(:name) { |n| ["Tacos", "Burritos", "Pizzas", "Salads", "Drinks"][n % 5] }
    position { 0 }
  end

  factory :item do
    restaurant
    description { "" }
    status     { "draft" }
    confidence { "suggested" }
    popularity { 0 }

    transient do
      sequence(:rotation_idx) { |n| n }
      ingredients { [] }
      tag_list    { [] }
    end

    name { ITEM_SAMPLES[(rotation_idx - 1) % ITEM_SAMPLES.size] }

    trait :published do
      status { "published" }
    end

    trait :confirmed do
      confidence { "confirmed" }
    end

    # Convenience: pass `ingredients: [ing1, ing2]` and the join rows
    # are created (which fires the after_save sync to ingredient_ids).

    after(:create) do |item, evaluator|
      evaluator.ingredients.each do |ingredient|
        ItemIngredient.create!(item: item, ingredient: ingredient,
                               confidence: item.confidence, source: "human")
      end
      evaluator.tag_list.each do |tag|
        ItemTag.create!(item: item, tag: tag,
                        confidence: item.confidence, source: "human")
      end
    end
  end
end
