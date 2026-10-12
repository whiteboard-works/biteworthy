# frozen_string_literal: true

# Catalog terms a Riverton import showed missing. "Ginger beer" matched
# beer (hiding a zero-proof drink from a celiac filter) and "Grey Goose"
# goose; a menu's "glazed nuts" matched nothing, so a tree-nut or peanut
# avoider saw the dish as safe; "carne asada" never meant beef; and
# "Chicken Fried Steak" matched chicken. Specific nuts gain a "<name> nuts"
# alias so the new bare "nuts" does not also fire on them. Production seeds only on first
# boot (see 20261005223000), so this carries the seed edit: aliases are
# merged, never replaced, and a node an admin placed elsewhere is left.
class AddMenuFalseFriendTerms < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  ALIASES = {
    "alcohol"               => [ "hard ginger beer", "hard root beer", "spiked root beer" ],
    "condiment-ginger-ale"  => [ "ginger beer" ],
    "meat-beef-skirt-steak" => [ "carne asada" ],
    # So "cashew nuts" is read whole, not as cashew plus Mixed Nuts (and
    # the peanut Mixed Nuts implies).
    "tree_nut-almond"       => [ "almond nuts" ],
    "tree_nut-cashew"       => [ "cashew nuts" ],
    "tree_nut-hazel"        => [ "hazel nuts" ],
    "tree_nut-walnut"       => [ "walnut nuts" ],
    "tree_nut-macadamia"    => [ "macadamia nuts" ],
    "tree_nut-pecan"        => [ "pecan nuts" ],
    "tree_nut-pistacia"     => [ "pistachio nuts" ]
  }.freeze

  INGREDIENTS = [
    { slug: "condiment-root-beer", name: "Root Beer", path: "condiment.root_beer",
      aliases: [], allergen: false },
    { slug: "meat-beef-chicken-fried-steak", name: "Chicken Fried Steak", path: "meat.beef.chicken_fried_steak",
      aliases: [ "country fried steak" ], allergen: false },
    { slug: "tree_nut-mixed-nuts", name: "Mixed Nuts", path: "tree_nut.mixed_nuts",
      aliases: [ "nuts", "glazed nuts", "candied nuts", "spiced nuts" ], allergen: true }
  ].freeze

  # The implications on the new nodes point at these, so they must exist
  # too or a mixed-nuts dish would imply nothing.
  REQUIRED = %w[legume-peanuts grain-wheat-breading].freeze

  def up
    # A fresh database runs migrations before db:seed, and the seed file
    # carries these rows; writing them here would leave orphans. The new
    # nodes need no parent row (production has no `condiment` root at all),
    # so this one check is the only guard.
    unless (ALIASES.keys + REQUIRED).all? { |slug| MigrationIngredient.exists?(slug: slug) }
      say "Taxonomy not seeded; skipping (db:seed carries these terms)"
      return
    end

    ALIASES.each do |slug, aliases|
      ing = MigrationIngredient.find_by!(slug: slug)
      ing.update!(aliases: Array(ing.aliases) | aliases)
    end

    INGREDIENTS.each do |attrs|
      ing = MigrationIngredient.find_or_initialize_by(slug: attrs[:slug])
      if ing.persisted? && ing.path.to_s != attrs[:path]
        next say("#{attrs[:slug]} exists at #{ing.path}; leaving it there")
      end

      ing.assign_attributes(attrs.merge(aliases: Array(ing.aliases) | attrs[:aliases]))
      ing.save!
    end
  end

  def down
    # Non-destructive: items may already reference these nodes.
  end
end
