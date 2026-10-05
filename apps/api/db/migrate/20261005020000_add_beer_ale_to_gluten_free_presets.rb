class AddBeerAleToGlutenFreePresets < ActiveRecord::Migration[8.0]
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
    # Ensure beer and ale ingredients exist in taxonomy.
    # If they're missing, create them idempotently with the same attributes
    # the seed uses (from db/seeds/ingredients.yml).
    beer = Ingredient.find_or_initialize_by(slug: "alcohol-beer")
    if beer.new_record?
      beer.assign_attributes(
        name: "Beer",
        path: "alcohol.beer",
        aliases: [],
        allergen: false
      )
      beer.save!
      say "Created missing ingredient: alcohol-beer"
    end

    ale = Ingredient.find_or_initialize_by(slug: "alcohol-ale")
    if ale.new_record?
      ale.assign_attributes(
        name: "Ale",
        path: "alcohol.ale",
        aliases: [],
        allergen: false
      )
      ale.save!
      say "Created missing ingredient: alcohol-ale"
    end

    # Add beer and ale to Celiac and Gluten-Free preset join tables
    %w[celiac gluten-free].each do |preset_slug|
      preset = DietaryProfile.find_by(slug: preset_slug)
      unless preset
        say "Warning: #{preset_slug} preset not found, skipping"
        next
      end

      [ beer, ale ].each do |ingredient|
        # Use find_or_create_by to be idempotent
        DietaryProfileIngredient.find_or_create_by!(
          dietary_profile_id: preset.id,
          ingredient_id: ingredient.id,
          rule: "avoid"
        )
      end

      say "Added beer/ale to #{preset_slug} preset"
    end

    # Backfill existing user profiles that have Celiac or Gluten-Free as their primary preset.
    # Profiles copy preset items into their avoid_ingredient_ids array (they don't just reference
    # the preset at filter time), so we need to update existing arrays.
    celiac = DietaryProfile.find_by(slug: "celiac")
    gluten_free = DietaryProfile.find_by(slug: "gluten-free")

    if celiac || gluten_free
      preset_ids = [ celiac&.id, gluten_free&.id ].compact
      beer_id = beer.id
      ale_id = ale.id
      updated_count = 0

      # Use update_all with array concatenation for efficiency and to avoid loading
      # all profiles into memory. PostgreSQL's array_cat concatenates arrays.
      # We use DISTINCT to avoid duplicates if beer or ale are already present.
      preset_ids.each do |preset_id|
        # For each profile with this preset, add beer and ale if not already present
        result = execute(<<~SQL.squish)
          UPDATE user_profiles
          SET avoid_ingredient_ids = (
            SELECT array_agg(DISTINCT unnest_val)
            FROM unnest(avoid_ingredient_ids || ARRAY['#{beer_id}', '#{ale_id}']::uuid[]) AS unnest_val
          )
          WHERE primary_dietary_profile_id = '#{preset_id}'
          AND NOT (avoid_ingredient_ids && ARRAY['#{beer_id}', '#{ale_id}']::uuid[])
        SQL

        # result.cmd_tuples returns the number of rows updated
        count = result.respond_to?(:cmd_tuples) ? result.cmd_tuples : 0
        updated_count += count
      end

      say "Updated #{updated_count} user profile(s) to include beer/ale"
    end
  end

  def down
    # Irreversible — this adds safety coverage, removing it would be dangerous.
    # The ingredients stay in the taxonomy (they may be used elsewhere), but
    # we could remove them from the preset join tables if really needed.
    raise ActiveRecord::IrreversibleMigration
  end
end
