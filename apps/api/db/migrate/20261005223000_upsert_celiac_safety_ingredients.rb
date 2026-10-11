# frozen_string_literal: true

# Upsert wheat-based ingredients and papadum for Celiac safety (#766).
#
# Production seeds only on FIRST boot (`db:prepare` in deploy.yml), so
# editing `db/seeds/ingredients.yml` doesn't reach live. This migration
# upserts the taxonomy additions as a one-time data change, idempotent
# and fail-loud (unknown path raises rather than silently creating orphans).
class UpsertCeliacSafetyIngredients < ActiveRecord::Migration[8.1]
  # Migration-local class to avoid coupling to app/models.
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  # New ingredients + alias updates from #766
  INGREDIENTS = [
    # Pancake: add "hotcake" alias
    { slug: "grain-wheat-pancake", name: "Pancake", path: "grain.wheat.pancake",
      aliases: [ "flapjack", "hotcake" ], allergen: true },

    # New wheat-based bread entries
    { slug: "grain-wheat-bread-biscuit", name: "Biscuit", path: "grain.wheat.bread.biscuit",
      aliases: [ "buttermilk biscuit" ], allergen: true },
    { slug: "grain-wheat-bread-english-muffin", name: "English Muffin",
      path: "grain.wheat.bread.english_muffin", aliases: [ "muffin" ], allergen: true },

    # New wheat-based preparation entries
    { slug: "grain-wheat-batter", name: "Batter", path: "grain.wheat.batter",
      aliases: [ "wheat batter", "flour batter" ], allergen: true },
    { slug: "grain-wheat-breading", name: "Breading", path: "grain.wheat.breading",
      aliases: [ "breaded", "bread coating" ], allergen: true },
    { slug: "grain-wheat-roux", name: "Roux", path: "grain.wheat.roux",
      aliases: [ "flour roux" ], allergen: true },
    { slug: "grain-wheat-gravy", name: "Wheat-Based Gravy", path: "grain.wheat.gravy",
      aliases: [ "country gravy", "sausage gravy", "white gravy", "cream gravy", "flour gravy" ],
      allergen: true },

    # Papadum (lentil-based, NOT wheat — prevents false positive)
    { slug: "legume-papadum", name: "Papadum", path: "legume.papadum",
      aliases: [ "poppadom", "papad", "appalam" ], allergen: false }
  ].freeze

  def up
    # Verify all parent paths exist before upserting (fail loud)
    parent_paths = INGREDIENTS.map { |i| i[:path].rpartition(".").first }.uniq.compact
    parent_paths.each do |path|
      raise "Parent ingredient path #{path} not found" unless MigrationIngredient.exists?(path: path)
    end

    INGREDIENTS.each do |attrs|
      ing = MigrationIngredient.find_or_initialize_by(slug: attrs[:slug])
      ing.assign_attributes(attrs)
      ing.save!
    end

    puts "Upserted #{INGREDIENTS.size} Celiac safety ingredients"

    # Verify Celiac and Gluten-Free presets still cover them (they avoid
    # grain.wheat.* via path prefix, so new descendants are automatic)
    celiac_ids = query_preset_ingredient_ids("celiac")
    gluten_free_ids = query_preset_ingredient_ids("gluten-free")

    wheat_slugs = INGREDIENTS.select { |i| i[:path].start_with?("grain.wheat") }.map { |i| i[:slug] }
    wheat_ids = MigrationIngredient.where(slug: wheat_slugs).pluck(:id)

    missing_celiac = wheat_ids - celiac_ids
    missing_gluten_free = wheat_ids - gluten_free_ids

    if missing_celiac.any? || missing_gluten_free.any?
      raise "Preset coverage incomplete: celiac missing #{missing_celiac.size}, " \
            "gluten-free missing #{missing_gluten_free.size}"
    end

    puts "Verified Celiac and Gluten-Free presets cover new wheat ingredients"
  end

  def down
    # Non-destructive: leave the ingredients (removing them breaks items)
    puts "Skipped ingredient removal (non-destructive)"
  end

  private

  # DietaryProfile + join expansion, SQL-only to avoid app coupling
  def query_preset_ingredient_ids(slug)
    result = ActiveRecord::Base.connection.execute(<<~SQL.squish)
      SELECT i.id
      FROM ingredients i
      WHERE i.path <@ (
        SELECT ARRAY_AGG(ing2.path)::ltree[]
        FROM dietary_profiles dp
        JOIN dietary_profile_ingredients dpi ON dpi.dietary_profile_id = dp.id
        JOIN ingredients ing2 ON ing2.id = dpi.ingredient_id
        WHERE dp.slug = '#{slug}' AND dpi.rule = 'avoid'
      )
    SQL
    result.map { |row| row["id"] }
  end
end
