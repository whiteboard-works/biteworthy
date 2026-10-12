# frozen_string_literal: true

# A Riverton import matched "French Toast" to French dressing and every
# "Italian …" dish (Italian Meatballs, "italian fig gin") to Italian
# dressing, through the bare aliases "french" and "italian"; and plural
# "peppers" (bell peppers on a menu) fell to black pepper. The bare
# aliases go, "French dressing" and "Italian dressing" still match, and
# bell pepper answers to "peppers" (the singular "pepper" stays black
# pepper: a catalog name beats an alias).
#
# Production seeds only on first boot (see 20261005223000), so this
# carries the seed edit. Only the named aliases are removed or added;
# anything else production holds is left alone.
class RetireFalseFriendAliases < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  REMOVE = {
    "condiment-dressings-french"  => [ "french" ],
    "condiment-dressings-italian" => [ "italian" ]
  }.freeze

  ADD = { "vegetable-bell-pepper" => [ "peppers" ] }.freeze

  # Each node on its own: a fresh database (migrations run before db:seed)
  # has none of them, and a node an admin renamed must not hold back the
  # other changes, since a migration never runs twice.
  def up
    REMOVE.each { |slug, aliases| change_aliases(slug) { |current| current - aliases } }
    ADD.each    { |slug, aliases| change_aliases(slug) { |current| current | aliases } }
  end

  def change_aliases(slug)
    ing = MigrationIngredient.find_by(slug: slug)
    return say("#{slug} not found; skipping (db:seed carries its aliases)") if ing.nil?

    ing.update!(aliases: yield(Array(ing.aliases)))
  end

  def down
    # Non-destructive: putting the false friends back would re-break matching.
  end
end
