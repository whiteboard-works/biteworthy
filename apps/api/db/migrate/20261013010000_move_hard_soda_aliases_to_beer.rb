# frozen_string_literal: true

# Follow-up to 20261013000000 (Codex on #923). "Hard ginger beer" went to
# the `alcohol` root, but the celiac presets avoid `alcohol.beer`, so a
# malt-based hard soda passed them; the aliases move to Beer. The named
# nuts the catalog still lacked a "<name> nuts" form for (ginkgo, hemp,
# hickory) gain one, so bare "nuts" does not also fire and imply peanut.
class MoveHardSodaAliasesToBeer < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  MOVED = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze

  ALIASES = {
    "alcohol-beer"     => MOVED,
    "tree_nut-ginkgo"  => [ "ginkgo nuts" ],
    "tree_nut-hemp"    => [ "hemp nuts" ],
    "tree_nut-hickory" => [ "hickory nuts" ]
  }.freeze

  def up
    unless (ALIASES.keys + [ "alcohol" ]).all? { |slug| MigrationIngredient.exists?(slug: slug) }
      say "Taxonomy not seeded; skipping (db:seed carries these terms)"
      return
    end

    root = MigrationIngredient.find_by!(slug: "alcohol")
    root.update!(aliases: Array(root.aliases) - MOVED)

    ALIASES.each do |slug, aliases|
      ing = MigrationIngredient.find_by!(slug: slug)
      ing.update!(aliases: Array(ing.aliases) | aliases)
    end
  end

  def down
    # Non-destructive.
  end
end
