FactoryBot.define do
  # Real preset names users will pick during onboarding ("I'm
  # vegetarian", "I have celiac"). Specs that exercise the
  # dietary_profile preset application read more naturally when the
  # presets are actually called Vegan / Celiac / Halal.
  DIETARY_PROFILE_SAMPLES = [
    { slug: "vegan",        name: "Vegan",        description: "No animal products of any kind." },
    { slug: "vegetarian",   name: "Vegetarian",   description: "No meat, poultry, or seafood." },
    { slug: "pescatarian",  name: "Pescatarian",  description: "Vegetarian + fish & shellfish." },
    { slug: "celiac",       name: "Celiac",       description: "Strict gluten-free for celiac disease." },
    { slug: "gluten-free",  name: "Gluten-Free",  description: "Avoids wheat-based gluten." },
    { slug: "dairy-free",   name: "Dairy-Free",   description: "Avoids all dairy products." },
    { slug: "halal",        name: "Halal",        description: "Halal dietary law." },
    { slug: "kosher",       name: "Kosher",       description: "Kosher dietary law." },
    { slug: "tree-nut-allergy", name: "Tree-Nut Allergy", description: "Avoids almonds, walnuts, cashews, and other tree nuts." },
    { slug: "peanut-allergy",   name: "Peanut Allergy",   description: "Avoids peanuts and peanut-derived ingredients." }
  ].freeze

  factory :dietary_profile do
    transient do
      sequence(:rotation_idx) { |n| n }
    end

    slug { DIETARY_PROFILE_SAMPLES[(rotation_idx - 1) % DIETARY_PROFILE_SAMPLES.size][:slug] }

    name        { (DIETARY_PROFILE_SAMPLES.find { |s| s[:slug] == slug } || {})[:name]        || slug.tr("-", " ").capitalize }
    description { (DIETARY_PROFILE_SAMPLES.find { |s| s[:slug] == slug } || {})[:description] || "Custom dietary profile" }
  end
end
