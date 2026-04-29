#!/usr/bin/env ruby
# frozen_string_literal: true
#
# One-shot importer that turns _legacy/db/seeds/0_ingredients.rb into
# apps/api/db/seeds/ingredients.yml — the structured catalog Phase 1.4
# ships against. The 2020 file mixed data and side-effects (each name
# was followed by find_or_create_by); we keep only the data, attach
# ltree paths, set the FDA big-9 allergen flag, and write YAML.
#
# Usage (from apps/api/):
#   bundle exec ruby script/import_legacy_ingredients.rb
#
# Output is deterministic — re-running produces a byte-for-byte
# identical YAML, so this file lives alongside the YAML for
# reproducibility (and so a future contributor can audit the
# transformation without reverse-engineering it from the YAML alone).

require "yaml"
require "set"

LEGACY_PATH    = File.expand_path("../../../_legacy/db/seeds/0_ingredients.rb", __dir__)
OUTPUT_PATH    = File.expand_path("../db/seeds/ingredients.yml", __dir__)

# Each entry: regex-name in the legacy file → { ltree path root,
# allergen flag, optional sub-paths derived from the variable name }.
#
# The 2020 file used variable names like `meat_swine` for sub-grouping;
# we preserve those as ltree segments so "all pork" lookups work via
# `path <@ 'meat.swine'`. Allergen flags here apply to the *entire*
# subtree — individual exceptions (e.g. peanut sub-tree under legume)
# are handled in the per-category section below.
CATEGORIES = [
  { var: "fruits",                path: "fruit",            allergen: false },
  { var: "vegetables",            path: "vegetable",        allergen: false },
  { var: "herbs",                 path: "herb",             allergen: false },
  { var: "nuts",                  path: "tree_nut",         allergen: true  }, # FDA: tree nuts
  { var: "bean_legume_pulses",    path: "legume",           allergen: false }, # peanut/soy fixed up below
  { var: "grains",                path: "grain",            allergen: false }, # wheat fixed up below
  { var: "meats_beef",            path: "meat.beef",        allergen: false },
  { var: "meat_lagomorphs",       path: "meat.lagomorph",   allergen: false },
  { var: "meat_marsupials",       path: "meat.marsupial",   allergen: false },
  { var: "meat_ovis_sheep",       path: "meat.ovine",       allergen: false },
  { var: "meat_swine",            path: "meat.swine",       allergen: false },
  { var: "meat_venison_cervidae", path: "meat.cervid",      allergen: false },
  { var: "meat_rodents",          path: "meat.rodent",      allergen: false },
  { var: "meat_mammals",          path: "meat.other",       allergen: false },
  { var: "meat_reptiles",         path: "meat.reptile",     allergen: false },
  { var: "meat_amphibians",       path: "meat.amphibian",   allergen: false },
  { var: "meat_poultry_birds",    path: "poultry.domestic", allergen: false },
  { var: "meat_game_birds",       path: "poultry.game",     allergen: false },
  { var: "meat_fish",             path: "fish",             allergen: true  }, # FDA: finned fish
  { var: "meat_echinoderms",      path: "shellfish.echinoderm", allergen: true }
].freeze

# Hand-curated supplements not in the 2020 file. The phase-1.md plan
# explicitly lists dairy / spices / animal-products as required path
# roots; sesame / shellfish are FDA big-9 allergens whose 2020
# coverage was thin or absent. These keep the YAML as the single
# source of truth — adding to the catalog from now on means editing
# the YAML directly, not re-running the importer.
SUPPLEMENTS = {
  "dairy" => {
    allergen: true,
    items: [
      "Milk", "Whole Milk", "Skim Milk", "Two Percent Milk", "Heavy Cream",
      "Half-and-Half", "Buttermilk", "Sour Cream", "Yogurt", "Greek Yogurt",
      "Kefir", "Butter", "Ghee", "Clarified Butter",
      "Cheddar", "Mozzarella", "Parmesan", "Pecorino Romano", "Feta",
      "Goat Cheese", "Cream Cheese", "Cottage Cheese", "Ricotta", "Mascarpone",
      "Burrata", "Brie", "Camembert", "Gruyère", "Emmental", "Manchego",
      "Provolone", "Asiago", "Gouda", "Edam", "Havarti", "Monterey Jack",
      "Pepper Jack", "Colby", "Swiss Cheese", "Blue Cheese", "Roquefort",
      "Gorgonzola", "Stilton", "Halloumi", "Paneer", "Queso Fresco",
      "Cotija", "Quark", "Crème Fraîche", "Condensed Milk", "Evaporated Milk",
      "Ice Cream", "Gelato", "Frozen Yogurt", "Whey", "Casein", "Milk Powder"
    ]
  },
  "egg" => {
    allergen: true,
    items: [
      "Chicken Egg", "Duck Egg", "Quail Egg", "Goose Egg", "Egg White",
      "Egg Yolk", "Egg Substitute"
    ]
  },
  "spice" => {
    allergen: false,
    items: [
      "Black Pepper", "White Pepper", "Pink Peppercorn", "Cayenne",
      "Paprika", "Smoked Paprika", "Hungarian Paprika", "Sweet Paprika",
      "Chili Powder", "Ancho Chili", "Chipotle", "Aleppo Pepper",
      "Cumin", "Coriander Seed", "Caraway Seed", "Fennel Seed",
      "Anise", "Star Anise", "Cardamom", "Green Cardamom", "Black Cardamom",
      "Cinnamon", "Cassia", "Clove", "Nutmeg", "Mace",
      "Allspice", "Juniper Berry", "Sumac", "Saffron", "Turmeric",
      "Ginger", "Galangal", "Curry Powder", "Garam Masala", "Five-Spice",
      "Za'atar", "Ras El Hanout", "Berbere", "Harissa", "Adobo Seasoning",
      "Old Bay", "Italian Seasoning", "Herbes de Provence", "Bay Leaf",
      "Mustard Seed", "Yellow Mustard Seed", "Brown Mustard Seed",
      "Fenugreek", "Asafoetida", "Nigella Seed", "Poppy Seed",
      "Vanilla Bean", "Cocoa Powder", "Cacao Nib", "Cacao Powder",
      "MSG", "Salt", "Kosher Salt", "Sea Salt", "Pink Himalayan Salt",
      "Smoked Salt", "Truffle Salt", "Garlic Salt", "Onion Powder",
      "Garlic Powder", "Celery Salt", "Lemon Pepper", "Cajun Seasoning",
      "Creole Seasoning", "Jerk Seasoning", "Tajín", "Furikake",
      "Shichimi Togarashi", "Gochugaru", "Sichuan Peppercorn"
    ]
  },
  "sesame" => {
    allergen: true,
    items: [
      "Sesame Seed", "Black Sesame Seed", "White Sesame Seed",
      "Sesame Oil", "Toasted Sesame Oil", "Tahini"
    ]
  },
  "shellfish.crustacean" => {
    allergen: true,
    items: [
      "Shrimp", "Prawn", "Crayfish", "Lobster", "Spiny Lobster",
      "Crab", "Snow Crab", "King Crab", "Blue Crab", "Dungeness Crab",
      "Soft-Shell Crab", "Krill", "Langoustine"
    ]
  },
  "shellfish.mollusk" => {
    allergen: true,
    items: [
      "Oyster", "Clam", "Mussel", "Scallop", "Bay Scallop", "Sea Scallop",
      "Squid", "Calamari", "Octopus", "Cuttlefish", "Abalone", "Whelk",
      "Periwinkle", "Conch"
    ]
  },
  "soy" => {
    allergen: true,
    items: [
      "Soybean", "Edamame", "Tofu", "Silken Tofu", "Firm Tofu", "Tempeh",
      "Soy Sauce", "Tamari", "Shoyu", "Miso", "White Miso", "Red Miso",
      "Soy Milk", "Soybean Oil", "TVP", "Natto", "Yuba"
    ]
  },
  "oil_and_fat" => {
    allergen: false,
    items: [
      "Olive Oil", "Extra-Virgin Olive Oil", "Canola Oil", "Vegetable Oil",
      "Sunflower Oil", "Safflower Oil", "Grapeseed Oil", "Avocado Oil",
      "Coconut Oil", "Palm Oil", "Lard", "Tallow", "Schmaltz",
      "Duck Fat", "Beef Fat", "Pork Fat", "Vegetable Shortening", "Margarine"
    ]
  },
  "sweetener" => {
    allergen: false,
    items: [
      "Cane Sugar", "White Sugar", "Brown Sugar", "Light Brown Sugar",
      "Dark Brown Sugar", "Powdered Sugar", "Turbinado Sugar", "Demerara Sugar",
      "Muscovado Sugar", "Coconut Sugar", "Maple Syrup", "Honey",
      "Agave Nectar", "Molasses", "Corn Syrup", "High-Fructose Corn Syrup",
      "Date Syrup", "Sorghum Syrup", "Stevia", "Erythritol", "Xylitol",
      "Monk Fruit", "Aspartame", "Sucralose", "Saccharin"
    ]
  },
  "condiment" => {
    allergen: false,
    items: [
      "Ketchup", "Mustard", "Yellow Mustard", "Dijon Mustard",
      "Whole-Grain Mustard", "Mayonnaise", "Aioli", "Sriracha", "Hot Sauce",
      "Tabasco", "Frank's RedHot", "Cholula", "Worcestershire Sauce",
      "Fish Sauce", "Oyster Sauce", "Hoisin Sauce", "Plum Sauce",
      "Sweet Chili Sauce", "Salsa", "Salsa Verde", "Pico de Gallo", "Mole",
      "Chimichurri", "Pesto", "Tzatziki", "Hummus", "Baba Ganoush",
      "BBQ Sauce", "A1 Sauce", "Chutney", "Mango Chutney", "Vinegar",
      "Apple Cider Vinegar", "Balsamic Vinegar", "Red Wine Vinegar",
      "White Wine Vinegar", "Rice Vinegar", "Sherry Vinegar", "Malt Vinegar"
    ]
  },
  "alcohol" => {
    allergen: false,
    items: [
      "Red Wine", "White Wine", "Rosé", "Champagne", "Sparkling Wine",
      "Sake", "Mirin", "Beer", "Lager", "Ale", "Stout", "IPA",
      "Vodka", "Gin", "Rum", "Tequila", "Mezcal", "Whiskey", "Bourbon",
      "Scotch", "Rye Whiskey", "Cognac", "Brandy", "Sherry", "Vermouth",
      "Port", "Marsala", "Madeira", "Triple Sec", "Cointreau", "Bitters"
    ]
  }
}.freeze

# Specific allergen overrides applied AFTER bulk categorization. These
# correct legacy categorization quirks: peanuts live in `legume` (correct
# botanically) but are an FDA top-9 allergen on their own; soy is the
# same. The wheat entry under `grain` is the gluten-bearing one we
# want flagged regardless of how the rest of `grain` is treated.
ALLERGEN_OVERRIDES = {
  # legume/peanut subtree → allergen
  /\Alegume\.peanut/      => true,
  /\Alegume\.soy/         => true,
  /\Alegume\.soybean/     => true,
  # specific grains → allergen (gluten-bearing)
  /\Agrain\.wheat/        => true,
  /\Agrain\.rye/          => true,
  /\Agrain\.barley/       => true,
  /\Agrain\.spelt/        => true,
  /\Agrain\.kamut/        => true,
  /\Agrain\.triticale/    => true
}.freeze

# Slugify a human-readable ingredient name into something safe for an
# `ingredients.slug` column AND a valid ltree label (lowercase ASCII
# letters, digits, and underscore — ltree labels disallow hyphens).
def slugify(name)
  s = name.dup
  s = s.tr("Çç", "Cc")
  s = s.tr("ÉéÈèÊêËë", "EeEeEeEe")
  s = s.tr("ÁáÀàÂâÄäÃã", "AaAaAaAaAa")
  s = s.tr("ÍíÌìÎîÏï", "IiIiIiIi")
  s = s.tr("ÓóÒòÔôÖöÕõ", "OoOoOoOoOo")
  s = s.tr("ÚúÙùÛûÜü", "UuUuUuUu")
  s = s.tr("Ññ", "Nn")
  s = s.tr("ÿ", "y")
  s = s.gsub(/[^a-zA-Z0-9]+/, "-")
  s = s.gsub(/-+/, "-")
  s = s.gsub(/^-|-$/, "")
  s.downcase
end

# ltree labels can only contain a-z, A-Z, 0-9, _. We use _ as the
# in-label separator and . as the segment separator, mirroring what
# Postgres's ltree implementation expects.
def ltree_label(name)
  slugify(name).tr("-", "_")
end

# Strip the parenthetical gloss ("Domestic pig (pork)" → "Domestic pig")
# so the user-facing name doesn't double up on info, but keep what
# was inside the parens as an alias.
def split_gloss(name)
  if (m = name.match(/\A(.+?)\s*\(([^)]+)\)\s*\z/))
    [m[1].strip, [m[2].strip]]
  else
    [name, []]
  end
end

# Some 2020 entries are continuation lines that escaped the parser
# (e.g. "Cherry of the Rio\n  Grande" became two entries). Filter the
# obvious bogus ones — single lowercase tokens that aren't real names.
BOGUS_NAMES = Set.new(%w[grande arrowhead]).freeze

# ---- 1. Parse the legacy file --------------------------------------------

raw = File.read(LEGACY_PATH)

def extract_block(raw, var_name)
  # Find `VAR = %w(` then read forward with a balanced-paren counter.
  # A naive `/%w\((.+?)\)/m` would terminate at the first `)`, which
  # truncates entries like "Domestic\ pig\ (pork)" mid-token.
  m = raw.match(/\b#{Regexp.escape(var_name)}\s*=\s*%w\(/)
  return [] unless m

  start = m.end(0)
  depth = 1
  i = start
  while i < raw.length && depth.positive?
    case raw[i]
    when "(" then depth += 1
    when ")" then depth -= 1
    end
    i += 1
  end
  body = raw[start...(i - 1)]

  # Split on UNESCAPED whitespace only — `\ ` (backslash-space) inside
  # a %w token is the Ruby idiom for embedding a space in a word, so
  # "Cream\ Cheese" needs to come back as a single token "Cream Cheese".
  body
    .split(/(?<!\\)\s+/)
    .reject(&:empty?)
    .map { |s| s.gsub(/\\ /, " ").strip }
    .reject(&:empty?)
end

records = []
seen_slugs = Set.new

CATEGORIES.each do |cat|
  names = extract_block(raw, cat[:var])
  names.each do |raw_name|
    next if BOGUS_NAMES.include?(raw_name.downcase)

    primary, aliases = split_gloss(raw_name)
    slug   = "#{cat[:path].tr('.', '-')}-#{slugify(primary)}"
    next unless seen_slugs.add?(slug)

    label = ltree_label(primary)
    path  = "#{cat[:path]}.#{label}"

    records << {
      "slug"     => slug,
      "name"     => primary,
      "path"     => path,
      "aliases"  => aliases,
      "allergen" => cat[:allergen]
    }
  end
end

# ---- 2. Layer the supplements --------------------------------------------

SUPPLEMENTS.each do |path_root, payload|
  payload[:items].each do |raw_name|
    primary, aliases = split_gloss(raw_name)
    slug = "#{path_root.tr('.', '-')}-#{slugify(primary)}"
    next unless seen_slugs.add?(slug)

    label = ltree_label(primary)
    path  = "#{path_root}.#{label}"

    records << {
      "slug"     => slug,
      "name"     => primary,
      "path"     => path,
      "aliases"  => aliases,
      "allergen" => payload[:allergen]
    }
  end
end

# ---- 3. Add the bare path-root rows so `<@` queries can hit them ----------
#
# Postgres's ltree `path <@ 'fruit'` only matches descendants of a node
# that *exists*. We need a row at every root and intermediate node so
# "avoid all fruit" or "avoid all dairy" finds something to sit on.
ROOTS = (
  CATEGORIES.map { |c| [c[:path], c[:allergen]] } +
  SUPPLEMENTS.map { |p, payload| [p, payload[:allergen]] }
).each_with_object({}) { |(p, a), h| h[p] ||= a; h[p] ||= a }

ROOTS.each_key do |path_root|
  segments = path_root.split(".")
  segments.each_with_index do |_, i|
    sub = segments[0..i].join(".")
    slug = sub.tr(".", "-")
    next unless seen_slugs.add?(slug)

    name = segments[0..i].last.tr("_", " ").split.map(&:capitalize).join(" ")
    records << {
      "slug"     => slug,
      "name"     => name,
      "path"     => sub,
      "aliases"  => [],
      "allergen" => ROOTS[sub] || ROOTS[path_root]
    }
  end
end

# ---- 4. Apply allergen overrides -----------------------------------------
records.each do |r|
  ALLERGEN_OVERRIDES.each do |regex, flag|
    r["allergen"] = flag if r["path"].match?(regex)
  end
end

# ---- 5. Sort + write ------------------------------------------------------
records.sort_by! { |r| r["path"] }

File.write(
  OUTPUT_PATH,
  "# Generated by script/import_legacy_ingredients.rb. Re-running the\n" \
  "# script reproduces this file exactly. Hand edits should be made\n" \
  "# directly to this YAML — the importer is for the 2020 backfill only.\n" \
  "---\n" +
  records.map { |r| YAML.dump(r).sub(/\A---\n/, "- ").gsub(/^/, "").lines.tap { |ls| ls[1..]&.each { |l| l.replace("  " + l) } }.join }.join
)

puts "Wrote #{records.size} ingredients → #{OUTPUT_PATH}"
puts "Allergens: #{records.count { |r| r['allergen'] }}"
