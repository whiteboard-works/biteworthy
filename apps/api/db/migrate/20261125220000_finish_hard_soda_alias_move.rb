# frozen_string_literal: true

# Follow-up to 20261013010000 (Codex on #925). That migration's
# all-or-nothing guard returned early when any of Ginkgo/Hemp/Hickory
# were missing (DeleteTaxonomyNode can remove them), so the hard-soda
# aliases stayed on the `alcohol` root and a celiac preset that avoids
# `alcohol.beer` still saw those dishes as safe.
#
# This run requires only the two alcohol nodes. Named-nut aliases are
# applied per node and skipped when that node is gone. Idempotent: a
# database that already took the first migration is a no-op. `down` does
# not put the aliases back on alcohol — that is the unsafe direction.
class FinishHardSodaAliasMove < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  MOVED = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze

  NUT_ALIASES = {
    "tree_nut-ginkgo"  => [ "ginkgo nuts" ],
    "tree_nut-hemp"    => [ "hemp nuts" ],
    "tree_nut-hickory" => [ "hickory nuts" ]
  }.freeze

  def up
    root = MigrationIngredient.find_by(slug: "alcohol")
    beer = MigrationIngredient.find_by(slug: "alcohol-beer")
    unless root && beer && root.id != beer.id
      say "Alcohol taxonomy not seeded; skipping hard-soda alias move"
      return
    end

    root.update!(aliases: Array(root.aliases) - MOVED)
    beer.update!(aliases: Array(beer.aliases) | MOVED)

    NUT_ALIASES.each do |slug, aliases|
      ing = MigrationIngredient.find_by(slug: slug)
      unless ing
        say "skipping #{slug}; node missing"
        next
      end

      ing.update!(aliases: Array(ing.aliases) | aliases)
    end
  end

  def down
    # Non-destructive.
  end
end
