class ExpandCeliacGlutenCoverage < ActiveRecord::Migration[8.0]
  # Isolated model classes to avoid future app model changes breaking this migration
  class Ingredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class DietaryProfile < ActiveRecord::Base
    self.table_name = "dietary_profiles"
  end

  class DietaryProfileIngredient < ActiveRecord::Base
    self.table_name = "dietary_profile_ingredients"
  end

  class UserProfile < ActiveRecord::Base
    self.table_name = "user_profiles"
  end

  def up
    # ===========================================
    # 1. Update existing ingredients with wheat connections
    # ===========================================

    # Soy sauce and teriyaki: most contain wheat
    # Remove tamari from soy sauce (it's gluten-free), keep shoyu
    soy_sauce = Ingredient.find_by(slug: "soy-soy-sauce")
    if soy_sauce
      current_aliases = Array(soy_sauce.aliases || [])
      # Keep only Shoyu, remove Tamari
      new_aliases = current_aliases.reject { |a| a.casecmp?("tamari") }.uniq
      if new_aliases != current_aliases
        soy_sauce.update!(aliases: new_aliases)
        say "Updated soy-soy-sauce aliases (removed tamari)"
      end
    end

    # Create tamari as a separate gluten-free ingredient
    tamari = Ingredient.find_or_initialize_by(slug: "soy-tamari")
    if tamari.new_record?
      tamari.assign_attributes(
        name: "Tamari",
        path: "soy.tamari",
        aliases: [ "gluten free soy sauce" ],
        allergen: false
      )
      tamari.save!
      say "Created ingredient: soy-tamari (gluten-free)"
    end

    # Gravy: traditionally wheat-thickened unless otherwise specified
    gravy = Ingredient.find_by(slug: "condiment-sauces-gravy")
    if gravy
      gravy.update!(allergen: true)
      say "Updated gravy to allergen: true"
    end

    # Malt vinegar already references barley malt, just ensure allergen flag
    malt_vinegar = Ingredient.find_by(slug: "condiment-malt-vinegar")
    if malt_vinegar
      malt_vinegar.update!(allergen: true)
      say "Updated malt-vinegar to allergen: true"
    end

    # ===========================================
    # 2. Create wheat-containing beer types
    # ===========================================

    porter = Ingredient.find_or_initialize_by(slug: "alcohol-porter")
    if porter.new_record?
      porter.assign_attributes(
        name: "Porter",
        path: "alcohol.porter",
        aliases: [],
        allergen: false
      )
      porter.save!
      say "Created ingredient: alcohol-porter"
    end

    pilsner = Ingredient.find_or_initialize_by(slug: "alcohol-pilsner")
    if pilsner.new_record?
      pilsner.assign_attributes(
        name: "Pilsner",
        path: "alcohol.pilsner",
        aliases: [ "pils" ],
        allergen: false
      )
      pilsner.save!
      say "Created ingredient: alcohol-pilsner"
    end

    # ===========================================
    # 3. Create wheat-based breads and wrappers
    # ===========================================

    roti = Ingredient.find_or_initialize_by(slug: "grain-wheat-bread-roti")
    if roti.new_record?
      roti.assign_attributes(
        name: "Roti",
        path: "grain.wheat.bread.roti",
        aliases: [],
        allergen: true
      )
      roti.save!
      say "Created ingredient: grain-wheat-bread-roti"
    end

    chapati = Ingredient.find_or_initialize_by(slug: "grain-wheat-bread-chapati")
    if chapati.new_record?
      chapati.assign_attributes(
        name: "Chapati",
        path: "grain.wheat.bread.chapati",
        aliases: [ "chapatti" ],
        allergen: true
      )
      chapati.save!
      say "Created ingredient: grain-wheat-bread-chapati"
    end

    paratha = Ingredient.find_or_initialize_by(slug: "grain-wheat-bread-paratha")
    if paratha.new_record?
      paratha.assign_attributes(
        name: "Paratha",
        path: "grain.wheat.bread.paratha",
        aliases: [],
        allergen: true
      )
      paratha.save!
      say "Created ingredient: grain-wheat-bread-paratha"
    end

    puri = Ingredient.find_or_initialize_by(slug: "grain-wheat-bread-puri")
    if puri.new_record?
      puri.assign_attributes(
        name: "Puri",
        path: "grain.wheat.bread.puri",
        aliases: [ "poori" ],
        allergen: true
      )
      puri.save!
      say "Created ingredient: grain-wheat-bread-puri"
    end

    # ===========================================
    # 4. Create wheat-based dumplings and wrappers
    # ===========================================

    momo = Ingredient.find_or_initialize_by(slug: "grain-wheat-dumpling-momo")
    if momo.new_record?
      momo.assign_attributes(
        name: "Momo",
        path: "grain.wheat.dumpling.momo",
        aliases: [ "momos" ],
        allergen: true
      )
      momo.save!
      say "Created ingredient: grain-wheat-dumpling-momo"
    end

    empanada = Ingredient.find_or_initialize_by(slug: "grain-wheat-empanada")
    if empanada.new_record?
      empanada.assign_attributes(
        name: "Empanada",
        path: "grain.wheat.empanada",
        aliases: [],
        allergen: true
      )
      empanada.save!
      say "Created ingredient: grain-wheat-empanada"
    end

    egg_roll = Ingredient.find_or_initialize_by(slug: "grain-wheat-egg-roll")
    if egg_roll.new_record?
      egg_roll.assign_attributes(
        name: "Egg Roll",
        path: "grain.wheat.egg_roll",
        aliases: [ "egg roll wrapper" ],
        allergen: true
      )
      egg_roll.save!
      say "Created ingredient: grain-wheat-egg-roll"
    end

    spring_roll = Ingredient.find_or_initialize_by(slug: "grain-wheat-spring-roll")
    if spring_roll.new_record?
      spring_roll.assign_attributes(
        name: "Spring Roll",
        path: "grain.wheat.spring_roll",
        aliases: [],
        allergen: true
      )
      spring_roll.save!
      say "Created ingredient: grain-wheat-spring-roll (wheat wrapper)"
    end

    wonton = Ingredient.find_or_initialize_by(slug: "grain-wheat-wonton")
    if wonton.new_record?
      wonton.assign_attributes(
        name: "Wonton",
        path: "grain.wheat.wonton",
        aliases: [ "wonton wrapper" ],
        allergen: true
      )
      wonton.save!
      say "Created ingredient: grain-wheat-wonton"
    end

    dumpling = Ingredient.find_or_initialize_by(slug: "grain-wheat-dumpling")
    if dumpling.new_record?
      dumpling.assign_attributes(
        name: "Dumpling",
        path: "grain.wheat.dumpling",
        aliases: [ "dumpling wrapper" ],
        allergen: true
      )
      dumpling.save!
      say "Created ingredient: grain-wheat-dumpling"
    end

    # ===========================================
    # 5. Create wheat-based prepared dishes
    # ===========================================

    schnitzel = Ingredient.find_or_initialize_by(slug: "grain-wheat-breaded-schnitzel")
    if schnitzel.new_record?
      schnitzel.assign_attributes(
        name: "Schnitzel",
        path: "grain.wheat.breaded.schnitzel",
        aliases: [],
        allergen: true
      )
      schnitzel.save!
      say "Created ingredient: grain-wheat-breaded-schnitzel"
    end

    katsu = Ingredient.find_or_initialize_by(slug: "grain-wheat-breaded-katsu")
    if katsu.new_record?
      katsu.assign_attributes(
        name: "Katsu",
        path: "grain.wheat.breaded.katsu",
        aliases: [],
        allergen: true
      )
      katsu.save!
      say "Created ingredient: grain-wheat-breaded-katsu"
    end

    croquette = Ingredient.find_or_initialize_by(slug: "grain-wheat-croquette")
    if croquette.new_record?
      croquette.assign_attributes(
        name: "Croquette",
        path: "grain.wheat.croquette",
        aliases: [],
        allergen: true
      )
      croquette.save!
      say "Created ingredient: grain-wheat-croquette"
    end

    # ===========================================
    # 6. Create additional wheat grains
    # ===========================================

    bulgur = Ingredient.find_or_initialize_by(slug: "grain-wheat-bulgur")
    if bulgur.new_record?
      bulgur.assign_attributes(
        name: "Bulgur",
        path: "grain.wheat.bulgur",
        aliases: [ "bulgur wheat", "burghul" ],
        allergen: true
      )
      bulgur.save!
      say "Created ingredient: grain-wheat-bulgur"
    end

    farro = Ingredient.find_or_initialize_by(slug: "grain-wheat-farro")
    if farro.new_record?
      farro.assign_attributes(
        name: "Farro",
        path: "grain.wheat.farro",
        aliases: [ "emmer", "einkorn" ],
        allergen: true
      )
      farro.save!
      say "Created ingredient: grain-wheat-farro"
    end

    # ===========================================
    # 7. Update breadcrumbs to add batter-related aliases
    # ===========================================

    breadcrumbs = Ingredient.find_by(slug: "grain-wheat-breadcrumbs")
    if breadcrumbs
      current_aliases = Array(breadcrumbs.aliases || [])
      new_aliases = (current_aliases + [ "breaded", "breading", "battered", "batter", "tempura batter" ]).uniq
      if new_aliases != current_aliases
        breadcrumbs.update!(aliases: new_aliases)
        say "Updated breadcrumbs with batter/breading aliases"
      end
    end

    # ===========================================
    # 8. Add new ingredients to Celiac and Gluten-Free presets
    # ===========================================

    # Beer types and items that contain wheat but aren't under grain.wheat.*
    new_gluten_slugs = [
      "alcohol-porter",
      "alcohol-pilsner",
      "alcohol-ipa",
      "alcohol-lager",
      "alcohol-stout",
      "soy-soy-sauce",
      "soy-teriyaki",
      "condiment-sauces-gravy",
      "condiment-malt-vinegar",
      "grain-barley-malt"
    ]

    %w[celiac gluten-free].each do |preset_slug|
      preset = DietaryProfile.find_by(slug: preset_slug)
      unless preset
        say "Warning: #{preset_slug} preset not found, skipping"
        next
      end

      new_gluten_slugs.each do |ingredient_slug|
        ingredient = Ingredient.find_by(slug: ingredient_slug)
        next unless ingredient

        DietaryProfileIngredient.find_or_create_by!(
          dietary_profile_id: preset.id,
          ingredient_id: ingredient.id,
          rule: "avoid"
        )
      end

      say "Added gluten-containing ingredients to #{preset_slug} preset"
    end

    # ===========================================
    # 9. Backfill existing user profiles
    # ===========================================

    celiac = DietaryProfile.find_by(slug: "celiac")
    gluten_free = DietaryProfile.find_by(slug: "gluten-free")

    if celiac || gluten_free
      preset_ids = [ celiac&.id, gluten_free&.id ].compact
      new_ingredient_ids = new_gluten_slugs.map { |slug| Ingredient.find_by(slug: slug)&.id }.compact

      if new_ingredient_ids.any?
        preset_ids.each do |preset_id|
          ids_sql = new_ingredient_ids.map { |id| "'#{id}'" }.join(", ")
          result = execute(<<~SQL.squish)
            UPDATE user_profiles
            SET avoid_ingredient_ids = (
              SELECT array_agg(DISTINCT unnest_val)
              FROM unnest(avoid_ingredient_ids || ARRAY[#{ids_sql}]::uuid[]) AS unnest_val
            )
            WHERE primary_dietary_profile_id = '#{preset_id}'
            AND NOT (avoid_ingredient_ids && ARRAY[#{ids_sql}]::uuid[])
          SQL

          count = result.respond_to?(:cmd_tuples) ? result.cmd_tuples : 0
          say "Updated #{count} user profile(s) for preset #{preset_id}"
        end
      end
    end

    say "Celiac/gluten coverage expansion complete"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
