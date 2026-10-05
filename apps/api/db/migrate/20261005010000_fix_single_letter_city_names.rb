class FixSingleLetterCityNames < ActiveRecord::Migration[8.0]
  def up
    # Clean up any cities with single-letter names or invalid data.
    # These likely came from bad imports or incomplete data entry.
    City.where("LENGTH(name) < 2").find_each do |city|
      if city.restaurants.exists?
        # If the city has restaurants, we need to be more careful.
        # Log it for manual review rather than deleting.
        Rails.logger.warn "City #{city.id} (#{city.name}, #{city.region}) has restaurants and needs manual review"
      else
        # Safe to delete cities with no restaurants.
        city.destroy
      end
    end
  end

  def down
    # Irreversible — bad data cleanup.
    raise ActiveRecord::IrreversibleMigration
  end
end
