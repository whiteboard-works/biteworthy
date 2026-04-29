FactoryBot.define do
  # Curated subset of the real ingredient taxonomy
  # (apps/api/db/seeds/ingredients.yml is the production source). Keeps
  # specs reading like real menu data — "dairy.cheese" instead of
  # "ingredient-7" — without coupling to whatever seeds exist at the
  # time the test runs.
  INGREDIENT_SAMPLES = [
    { slug: "dairy",            name: "Dairy",         path: "dairy",           allergen: true,  aliases: %w[milk lactose] },
    { slug: "dairy-cheese",     name: "Cheese",        path: "dairy.cheese",    allergen: true,  aliases: %w[fromage queso] },
    { slug: "dairy-butter",     name: "Butter",        path: "dairy.butter",    allergen: true,  aliases: %w[ghee] },
    { slug: "dairy-cream",      name: "Cream",         path: "dairy.cream",     allergen: true,  aliases: %w[creme half-and-half] },
    { slug: "egg",              name: "Egg",           path: "egg",             allergen: true,  aliases: %w[eggs] },
    { slug: "fish-salmon",      name: "Salmon",        path: "fish.salmon",     allergen: true,  aliases: %w[lox] },
    { slug: "fish-tuna",        name: "Tuna",          path: "fish.tuna",       allergen: true,  aliases: %w[ahi] },
    { slug: "shellfish-shrimp", name: "Shrimp",        path: "shellfish.shrimp", allergen: true, aliases: %w[prawn] },
    { slug: "tree-nut-almond",  name: "Almond",        path: "tree_nut.almond", allergen: true,  aliases: %w[almonds] },
    { slug: "tree-nut-walnut",  name: "Walnut",        path: "tree_nut.walnut", allergen: true,  aliases: %w[walnuts] },
    { slug: "peanut",           name: "Peanut",        path: "peanut",          allergen: true,  aliases: %w[groundnut] },
    { slug: "soy",              name: "Soy",           path: "soy",             allergen: true,  aliases: %w[soya] },
    { slug: "wheat",            name: "Wheat",         path: "wheat",           allergen: true,  aliases: %w[gluten flour] },
    { slug: "sesame",           name: "Sesame",        path: "sesame",          allergen: true,  aliases: %w[tahini] },
    { slug: "meat-beef",        name: "Beef",          path: "meat.beef",       allergen: false, aliases: %w[steak] },
    { slug: "meat-pork",        name: "Pork",          path: "meat.pork",       allergen: false, aliases: %w[bacon ham] },
    { slug: "poultry-chicken",  name: "Chicken",       path: "poultry.chicken", allergen: false, aliases: %w[hen] },
    { slug: "vegetable-onion",  name: "Onion",         path: "vegetable.onion", allergen: false, aliases: %w[onions scallion] },
    { slug: "vegetable-garlic", name: "Garlic",        path: "vegetable.garlic", allergen: false, aliases: %w[ajo] },
    { slug: "vegetable-tomato", name: "Tomato",        path: "vegetable.tomato", allergen: false, aliases: %w[tomatoes] },
    { slug: "fruit-lime",       name: "Lime",          path: "fruit.lime",      allergen: false, aliases: %w[limes] },
    { slug: "herb-cilantro",    name: "Cilantro",      path: "herb.cilantro",   allergen: false, aliases: %w[coriander] },
    { slug: "spice-cumin",      name: "Cumin",         path: "spice.cumin",     allergen: false, aliases: %w[jeera] },
    { slug: "grain-rice",       name: "Rice",          path: "grain.rice",      allergen: false, aliases: %w[arroz] },
    { slug: "grain-corn",       name: "Corn",          path: "grain.corn",      allergen: false, aliases: %w[maize] },
    { slug: "legume-bean-black",name: "Black Bean",    path: "legume.bean.black", allergen: false, aliases: %w[frijoles_negros] }
  ].freeze

  factory :ingredient do
    transient do
      sequence(:rotation_idx) { |n| n }
    end

    # When the caller doesn't specify a slug, rotate through the curated
    # list. When they do, the explicit slug wins and the other attributes
    # below look it up so name/path/aliases/allergen stay coherent.
    slug { INGREDIENT_SAMPLES[(rotation_idx - 1) % INGREDIENT_SAMPLES.size][:slug] }

    name     { (INGREDIENT_SAMPLES.find { |s| s[:slug] == slug } || {})[:name]     || slug.tr("-", " ").capitalize }
    path     { (INGREDIENT_SAMPLES.find { |s| s[:slug] == slug } || {})[:path]     || slug.tr("-", "_") }
    aliases  { (INGREDIENT_SAMPLES.find { |s| s[:slug] == slug } || {})[:aliases]  || [] }
    allergen { (INGREDIENT_SAMPLES.find { |s| s[:slug] == slug } || {}).fetch(:allergen, false) }

    trait :allergen do
      allergen { true }
    end
  end
end
