class AddChineseCuisineTag < ActiveRecord::Migration[8.0]
  # Isolated model class to avoid future app model changes breaking this migration
  class Tag < ActiveRecord::Base
    self.table_name = "tags"
  end

  def up
    # Ensure chinese cuisine tag exists in taxonomy.
    # If it's missing, create it idempotently with the same attributes
    # the seed uses (from db/seeds/tags.yml).
    chinese = Tag.find_or_initialize_by(slug: "chinese")
    if chinese.new_record?
      chinese.assign_attributes(
        name: "Chinese",
        family: "cuisine",
        path: "cuisine.chinese"
      )
      chinese.save!
      say "Created Chinese cuisine tag"
    else
      say "Chinese cuisine tag already exists"
    end
  end

  def down
    # Irreversible — tags may be in use by items/enrichment.
    # Removing the tag would orphan those associations.
    raise ActiveRecord::IrreversibleMigration
  end
end
