# frozen_string_literal: true

# Laan Thai (WBW-244 / WBW-246): glass/cellophane noodles and bean sprouts
# had no catalog node, so "glass noodles" matched wheat pasta, and egg
# pasta / wonton wrappers had no egg allergen link (the SLUG_TAGS half
# lives in TagDeriver; this is the production seed carry). Production
# seeds only on first boot, so the YAML edit alone never reaches live.
#
# Aliases are merged, never replaced. New nodes are upserted. A node an
# admin placed on a different path is left there.
class AddThaiNoodleCatalogTerms < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  ALIASES = {
    "grain-rice-noodle"      => [ "rice noodles" ],
    "grain-wheat-noodle-egg" => [ "egg noodles" ],
    "grain-wheat-wonton"     => [ "egg wonton wrapper" ]
  }.freeze

  INGREDIENTS = [
    { slug: "grain-rice-noodle-glass", name: "Glass Noodle", path: "grain.rice.noodle.glass",
      aliases: [
        "glass noodles", "cellophane noodle", "cellophane noodles",
        "bean thread", "bean thread noodle", "bean thread noodles",
        "mung bean noodle", "mung bean noodles", "woon sen", "wun sen"
      ], allergen: false },
    { slug: "grain-wheat-pasta-egg", name: "Egg Pasta", path: "grain.wheat.pasta.egg",
      aliases: [ "egg pasta" ], allergen: true },
    { slug: "vegetable-bean-sprout", name: "Bean Sprout", path: "vegetable.bean_sprout",
      aliases: [ "bean sprouts", "mung bean sprouts" ], allergen: false }
  ].freeze

  def up
    unless ALIASES.keys.all? { |slug| MigrationIngredient.exists?(slug: slug) }
      say "Taxonomy not seeded; skipping (db:seed carries these terms)"
      return
    end

    ALIASES.each do |slug, aliases|
      ing = MigrationIngredient.find_by!(slug: slug)
      ing.update!(aliases: merge_aliases(ing.aliases, aliases))
    end

    INGREDIENTS.each { |attrs| upsert_ingredient!(attrs) }
  end

  def down
    # Non-destructive: items may already reference these nodes.
  end

  private

  def upsert_ingredient!(attrs)
    ing = MigrationIngredient.find_or_initialize_by(slug: attrs[:slug])
    if ing.persisted? && ing.path.to_s != attrs[:path]
      say "#{attrs[:slug]} exists at #{ing.path}; leaving it there (wanted #{attrs[:path]})"
      return
    end

    ing.assign_attributes(attrs.merge(aliases: merge_aliases(ing.aliases, attrs[:aliases])))
    ing.save!
  end

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
