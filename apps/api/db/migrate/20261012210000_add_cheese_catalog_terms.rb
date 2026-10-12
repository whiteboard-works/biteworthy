# frozen_string_literal: true

# A Riverton import left bare "cheese" unresolved on a dozen dishes and
# "grana padano", "stracciatella", and "scamorza" with no catalog term,
# so those dishes carried no dairy row and a dairy-avoider saw them as
# safe. Bare "cheese" now resolves to the dairy root; the matcher's
# longest-match rule keeps "goat cheese" on its own node.
#
# Production seeds only on first boot, so the seed edit alone never
# reaches live (see 20261005223000). Aliases are merged with whatever
# production already carries, never replaced; new nodes are upserted.
class AddCheeseCatalogTerms < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  ALIASES = { "dairy" => [ "cheese" ] }.freeze

  INGREDIENTS = [
    { slug: "dairy-grana-padano", name: "Grana Padano", path: "dairy.grana_padano",
      aliases: [ "grana" ], allergen: true },
    { slug: "dairy-stracciatella", name: "Stracciatella", path: "dairy.stracciatella",
      aliases: [], allergen: true },
    { slug: "dairy-scamorza", name: "Scamorza", path: "dairy.scamorza",
      aliases: [], allergen: true }
  ].freeze

  def up
    # A fresh database runs migrations before db:seed, and the seed file
    # carries these rows; writing them here would leave orphans.
    unless ALIASES.keys.all? { |slug| MigrationIngredient.exists?(slug: slug) }
      puts "Taxonomy not seeded; skipping (db:seed carries these terms)"
      return
    end

    ALIASES.each do |slug, aliases|
      ing = MigrationIngredient.find_by!(slug: slug)
      ing.update!(aliases: Array(ing.aliases) | aliases)
    end

    INGREDIENTS.each do |attrs|
      ing = MigrationIngredient.find_or_initialize_by(slug: attrs[:slug])
      # Never move a node an admin placed elsewhere, and never fail the
      # deploy over it: the rest of the change still protects people.
      if ing.persisted? && ing.path.to_s != attrs[:path]
        puts "#{attrs[:slug]} exists at #{ing.path}; leaving it there (wanted #{attrs[:path]})"
        next
      end

      ing.assign_attributes(attrs.merge(aliases: Array(ing.aliases) | attrs[:aliases]))
      ing.save!
    end
  end

  def down
    # Non-destructive: items may already reference these nodes.
  end
end
