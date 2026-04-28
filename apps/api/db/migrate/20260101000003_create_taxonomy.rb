class CreateTaxonomy < ActiveRecord::Migration[8.0]
  # Ingredients and Tags are both hierarchical taxonomies stored with ltree
  # paths. ltree gives us "all descendants of X" (`path <@ 'fruit'`) in one
  # indexed query — this powers "avoid all dairy" without listing every
  # cheese variant.
  #
  # Ingredients are CLOSED: only admins (and the AI ingestion pipeline,
  # gated by review) can introduce new nodes. This is required for
  # medical-grade allergen filtering.
  #
  # Tags are OPEN with moderation: contributors can suggest new tags.
  def change
    create_table :ingredients, id: :uuid do |t|
      t.string  :slug,    null: false
      t.string  :name,    null: false
      t.column  :path,    :ltree, null: false
      t.text    :aliases, array: true, default: [], null: false
      t.boolean :allergen, default: false, null: false
      t.timestamps
    end
    add_index :ingredients, :slug, unique: true
    add_index :ingredients, :path, using: :gist
    add_index :ingredients, :name, opclass: :gin_trgm_ops, using: :gin
    add_index :ingredients, :aliases, using: :gin

    create_table :tags, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :family, null: false # diet | allergen | cuisine | prep | flavor
      t.column :path, :ltree, null: false
      t.string :description
      t.timestamps
    end
    add_index :tags, :slug, unique: true
    add_index :tags, :path, using: :gist
    add_index :tags, :family

    # Curated bundles ("Celiac", "Vegan") that pre-fill a UserProfile.
    create_table :dietary_profiles, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text   :description
      t.timestamps
    end
    add_index :dietary_profiles, :slug, unique: true

    create_table :dietary_profile_ingredients, id: :uuid do |t|
      t.references :dietary_profile, type: :uuid, null: false, foreign_key: true
      t.references :ingredient,      type: :uuid, null: false, foreign_key: true
      t.string :rule, null: false, default: "avoid" # avoid | prefer
    end
    add_index :dietary_profile_ingredients,
              [:dietary_profile_id, :ingredient_id],
              unique: true,
              name: "idx_dpi_unique"

    create_table :dietary_profile_tags, id: :uuid do |t|
      t.references :dietary_profile, type: :uuid, null: false, foreign_key: true
      t.references :tag,             type: :uuid, null: false, foreign_key: true
      t.string :rule, null: false, default: "avoid"
    end
    add_index :dietary_profile_tags,
              [:dietary_profile_id, :tag_id],
              unique: true,
              name: "idx_dpt_unique"
  end
end
