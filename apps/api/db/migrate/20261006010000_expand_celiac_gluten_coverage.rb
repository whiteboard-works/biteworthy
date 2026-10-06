# frozen_string_literal: true

# Catch hidden gluten sources the Celiac / gluten-free presets still miss.
#
# Follows 20261005223000_upsert_celiac_safety_ingredients: idempotent
# upserts keyed on slug. Differences required by review of that
# migration: MERGE aliases (never overwrite), `say` not `puts`, and no
# raise when the ingredients table is empty (schema:load before seeds).
class ExpandCeliacGlutenCoverage < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  # New rows + alias additions. Existing aliases are unioned, not replaced.
  UPSERTS = [
    { slug: "alcohol-porter", name: "Porter", path: "alcohol.beer.porter",
      aliases: [], allergen: false },
    { slug: "alcohol-pilsner", name: "Pilsner", path: "alcohol.beer.pilsner",
      aliases: [ "pils" ], allergen: false },
    { slug: "soy-tamari", name: "Tamari", path: "soy.tamari",
      aliases: [ "tamari sauce", "gluten free soy sauce" ], allergen: true },
    { slug: "grain-wheat-batter", name: "Batter", path: "grain.wheat.batter",
      aliases: [ "battered", "tempura batter" ], allergen: true },
    { slug: "grain-wheat-breading", name: "Breading", path: "grain.wheat.breading",
      aliases: [ "crusted", "panko crusted" ], allergen: true },
    { slug: "grain-barley-malt", name: "Malt", path: "grain.barley.malt",
      aliases: [ "malted" ], allergen: true },
    { slug: "grain-wheat-noodle-ramen", name: "Ramen Noodle", path: "grain.wheat.noodle.ramen",
      aliases: [ "ramen" ], allergen: true },
    { slug: "grain-wheat-bread-roti", name: "Roti", path: "grain.wheat.bread.roti",
      aliases: [], allergen: true },
    { slug: "grain-wheat-bread-chapati", name: "Chapati", path: "grain.wheat.bread.chapati",
      aliases: [ "chapatti" ], allergen: true },
    { slug: "grain-wheat-bread-paratha", name: "Paratha", path: "grain.wheat.bread.paratha",
      aliases: [], allergen: true },
    { slug: "grain-wheat-bread-puri", name: "Puri", path: "grain.wheat.bread.puri",
      aliases: [ "poori" ], allergen: true },
    { slug: "grain-wheat-dumpling", name: "Dumpling", path: "grain.wheat.dumpling",
      aliases: [ "dumpling wrapper" ], allergen: true },
    { slug: "grain-wheat-dumpling-momo", name: "Momo", path: "grain.wheat.dumpling.momo",
      aliases: [ "momos" ], allergen: true },
    { slug: "grain-wheat-empanada", name: "Empanada", path: "grain.wheat.empanada",
      aliases: [], allergen: true },
    { slug: "grain-wheat-egg-roll", name: "Egg Roll", path: "grain.wheat.egg_roll",
      aliases: [ "egg roll wrapper" ], allergen: true },
    { slug: "grain-wheat-spring-roll", name: "Spring Roll", path: "grain.wheat.spring_roll",
      aliases: [], allergen: true },
    { slug: "grain-wheat-wonton", name: "Wonton", path: "grain.wheat.wonton",
      aliases: [ "wonton wrapper" ], allergen: true },
    { slug: "grain-wheat-schnitzel", name: "Schnitzel", path: "grain.wheat.schnitzel",
      aliases: [], allergen: true },
    { slug: "grain-wheat-katsu", name: "Katsu", path: "grain.wheat.katsu",
      aliases: [], allergen: true },
    { slug: "grain-wheat-croquette", name: "Croquette", path: "grain.wheat.croquette",
      aliases: [], allergen: true },
    { slug: "grain-wheat-bulgur", name: "Bulgur", path: "grain.wheat.bulgur",
      aliases: [ "bulgur wheat", "burghul" ], allergen: true },
    { slug: "grain-wheat-farro", name: "Farro", path: "grain.wheat.farro",
      aliases: [ "emmer" ], allergen: true }
  ].freeze

  BEER_STYLE_PATHS = {
    "alcohol-ipa" => "alcohol.beer.ipa",
    "alcohol-lager" => "alcohol.beer.lager",
    "alcohol-stout" => "alcohol.beer.stout"
  }.freeze

  def up
    unless MigrationIngredient.table_exists? && MigrationIngredient.any?
      say "Ingredients table empty — upserting rows so an unseeded DB still migrates"
    end

    BEER_STYLE_PATHS.each do |slug, path|
      ing = MigrationIngredient.find_by(slug: slug)
      unless ing
        say "Skipped repath of missing #{slug}"
        next
      end
      next if ing.path == path

      ing.update!(path: path)
      say "Repathed #{slug} to #{path}"
    end

    soy_sauce = MigrationIngredient.find_by(slug: "soy-soy-sauce")
    if soy_sauce
      stripped = Array(soy_sauce.aliases).reject { |alias_name| alias_name.to_s.casecmp?("tamari") }
      if stripped != Array(soy_sauce.aliases)
        soy_sauce.update!(aliases: stripped)
        say "Removed tamari from soy-soy-sauce aliases (tamari stays gluten-free)"
      end
    else
      say "Skipped tamari split — soy-soy-sauce is missing"
    end

    UPSERTS.each { |attrs| upsert_ingredient!(attrs) }

    say "Celiac/gluten coverage expansion complete"
  end

  def down
    say "Skipped ingredient removal (non-destructive)"
  end

  private

  def upsert_ingredient!(attrs)
    ing = MigrationIngredient.find_or_initialize_by(slug: attrs[:slug])
    merged_aliases = merge_aliases(ing.aliases, attrs[:aliases])

    if ing.new_record?
      ing.assign_attributes(attrs.merge(aliases: merged_aliases))
      ing.save!
      say "Created ingredient: #{attrs[:slug]}"
    else
      updates = { aliases: merged_aliases }
      updates[:path] = attrs[:path] if ing.path.blank?
      ing.update!(updates)
      say "Merged aliases for #{attrs[:slug]}"
    end
  end

  # Case-insensitive union; keep the first casing we saw.
  def merge_aliases(existing, incoming)
    seen = {}
    (Array(existing) + Array(incoming)).each do |alias_name|
      key = alias_name.to_s.strip
      next if key.empty?

      seen[key.downcase] ||= key
    end
    seen.values
  end
end
