class AddBeerAleToGlutenFreePresets < ActiveRecord::Migration[8.0]
  def up
    # Find beer and ale ingredients
    beer = Ingredient.find_by(slug: "alcohol-beer")
    ale = Ingredient.find_by(slug: "alcohol-ale")

    unless beer && ale
      Rails.logger.warn "Beer or Ale ingredients not found in taxonomy. Run db:seed first."
      return
    end

    # Update Celiac and Gluten-Free presets
    %w[celiac gluten-free].each do |preset_slug|
      preset = DietaryProfile.find_by(slug: preset_slug)
      next unless preset

      # Add beer and ale to the preset if not already present
      [beer, ale].each do |ingredient|
        DietaryProfileIngredient.find_or_create_by!(
          dietary_profile: preset,
          ingredient: ingredient,
          rule: "avoid"
        )
      end

      Rails.logger.info "Added beer/ale to #{preset_slug} preset"
    end

    # Update existing user profiles that have Celiac or Gluten-Free as their primary preset
    celiac_preset = DietaryProfile.find_by(slug: "celiac")
    gluten_free_preset = DietaryProfile.find_by(slug: "gluten-free")

    if celiac_preset || gluten_free_preset
      preset_ids = [celiac_preset&.id, gluten_free_preset&.id].compact
      profiles_to_update = UserProfile.where(primary_dietary_profile_id: preset_ids)

      profiles_to_update.find_each do |profile|
        # Only add if not already in their custom avoid list
        beer_id = beer.id
        ale_id = ale.id

        updated = false
        unless profile.avoid_ingredient_ids.include?(beer_id)
          profile.avoid_ingredient_ids = profile.avoid_ingredient_ids + [beer_id]
          updated = true
        end

        unless profile.avoid_ingredient_ids.include?(ale_id)
          profile.avoid_ingredient_ids = profile.avoid_ingredient_ids + [ale_id]
          updated = true
        end

        if updated
          profile.save!(validate: false) # Skip validations to avoid triggering other checks
          Rails.logger.info "Updated user profile #{profile.id} to include beer/ale"
        end
      end

      Rails.logger.info "Updated #{profiles_to_update.count} user profiles with beer/ale"
    end
  end

  def down
    # Irreversible — this adds safety coverage, removing it would be dangerous
    raise ActiveRecord::IrreversibleMigration
  end
end
