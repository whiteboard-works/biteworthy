FactoryBot.define do
  # Curated tag taxonomy mirroring the five families documented in
  # docs/schema.md (diet | allergen | cuisine | prep | flavor). Tags
  # in tests should look like the real thing — "diet.vegan",
  # "cuisine.mexican" — so failures read like menu data.
  TAG_SAMPLES = [
    { slug: "diet-vegan",         name: "Vegan",         family: "diet",     path: "diet.vegan" },
    { slug: "diet-vegetarian",    name: "Vegetarian",    family: "diet",     path: "diet.vegetarian" },
    { slug: "diet-pescatarian",   name: "Pescatarian",   family: "diet",     path: "diet.pescatarian" },
    { slug: "diet-gluten-free",   name: "Gluten-Free",   family: "diet",     path: "diet.gluten_free" },
    { slug: "diet-keto",          name: "Keto",          family: "diet",     path: "diet.keto" },
    { slug: "diet-halal",         name: "Halal",         family: "diet",     path: "diet.halal" },
    { slug: "diet-kosher",        name: "Kosher",        family: "diet",     path: "diet.kosher" },
    { slug: "allergen-contains-dairy",   name: "Contains Dairy",   family: "allergen", path: "allergen.contains_dairy" },
    { slug: "allergen-contains-egg",     name: "Contains Egg",     family: "allergen", path: "allergen.contains_egg" },
    { slug: "allergen-contains-tree-nut",name: "Contains Tree Nut",family: "allergen", path: "allergen.contains_tree_nut" },
    { slug: "allergen-contains-peanut",  name: "Contains Peanut",  family: "allergen", path: "allergen.contains_peanut" },
    { slug: "allergen-contains-shellfish",name: "Contains Shellfish",family: "allergen",path: "allergen.contains_shellfish" },
    { slug: "cuisine-mexican",    name: "Mexican",       family: "cuisine",  path: "cuisine.mexican" },
    { slug: "cuisine-italian",    name: "Italian",       family: "cuisine",  path: "cuisine.italian" },
    { slug: "cuisine-japanese",   name: "Japanese",      family: "cuisine",  path: "cuisine.japanese" },
    { slug: "cuisine-thai",       name: "Thai",          family: "cuisine",  path: "cuisine.thai" },
    { slug: "cuisine-american",   name: "American",      family: "cuisine",  path: "cuisine.american" },
    { slug: "prep-grilled",       name: "Grilled",       family: "prep",     path: "prep.grilled" },
    { slug: "prep-fried",         name: "Fried",         family: "prep",     path: "prep.fried" },
    { slug: "prep-raw",           name: "Raw",           family: "prep",     path: "prep.raw" },
    { slug: "prep-baked",         name: "Baked",         family: "prep",     path: "prep.baked" },
    { slug: "flavor-spicy",       name: "Spicy",         family: "flavor",   path: "flavor.spicy" },
    { slug: "flavor-sweet",       name: "Sweet",         family: "flavor",   path: "flavor.sweet" },
    { slug: "flavor-umami",       name: "Umami",         family: "flavor",   path: "flavor.umami" }
  ].freeze

  factory :tag do
    transient do
      sequence(:rotation_idx) { |n| n }
    end

    slug { TAG_SAMPLES[(rotation_idx - 1) % TAG_SAMPLES.size][:slug] }

    name   { (TAG_SAMPLES.find { |s| s[:slug] == slug } || {})[:name]   || slug.tr("-", " ").capitalize }
    family { (TAG_SAMPLES.find { |s| s[:slug] == slug } || {})[:family] || "diet" }
    path   { (TAG_SAMPLES.find { |s| s[:slug] == slug } || {})[:path]   || slug.tr("-", "_") }
  end
end
