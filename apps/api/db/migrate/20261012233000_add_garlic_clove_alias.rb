# frozen_string_literal: true

# "Garlic cloves" matched garlic and then the clove spice: the matcher's
# plural fallback turned the leftover "cloves" into `spice-clove`, hiding
# ordinary garlic dishes from a clove-avoider. "garlic clove" as an alias
# of garlic is the longer match and consumes both words. Production seeds
# only on first boot (see 20261005223000), so this carries the seed edit.
class AddGarlicCloveAlias < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  def up
    garlic = MigrationIngredient.find_by(slug: "vegetable-garlic")
    return say("vegetable-garlic not found; skipping (db:seed carries the alias)") if garlic.nil?

    garlic.update!(aliases: Array(garlic.aliases) | [ "garlic clove" ])
  end

  def down
    # Non-destructive.
  end
end
