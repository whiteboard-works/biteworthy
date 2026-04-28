class CreateMenusAndItems < ActiveRecord::Migration[8.0]
  def change
    create_table :menus, id: :uuid do |t|
      t.references :restaurant, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false, default: "Main"
      t.text   :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :menu_sections, id: :uuid do |t|
      t.references :menu, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false # e.g., "Appetizers", "Tacos"
      t.text   :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :items, id: :uuid do |t|
      t.references :restaurant,   type: :uuid, null: false, foreign_key: true
      t.references :menu_section, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.text   :description
      t.string :status, null: false, default: "draft"      # draft | published | removed
      t.string :confidence, null: false, default: "suggested" # confirmed | suggested | inferred
      t.integer :popularity, null: false, default: 0       # used to break ties in sort

      # Denormalized arrays for blazing-fast filter queries.
      # Kept in sync via ItemTag / ItemIngredient model callbacks.
      t.uuid :ingredient_ids, array: true, default: [], null: false
      t.uuid :tag_ids,        array: true, default: [], null: false

      t.references :created_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :items, [:restaurant_id, :status]
    add_index :items, :ingredient_ids, using: :gin
    add_index :items, :tag_ids,        using: :gin
    add_index :items, :name, opclass: :gin_trgm_ops, using: :gin

    create_table :item_variants, id: :uuid do |t|
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.string  :size               # "Small", "12 oz", null = single-size
      t.integer :price_cents        # null when intentionally unpriced
      t.string  :currency, default: "USD"
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :item_modifiers, id: :uuid do |t|
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false              # choice | addition | side
      t.integer :price_cents
      t.uuid :ingredient_ids, array: true, default: [], null: false
      t.uuid :tag_ids,        array: true, default: [], null: false
      t.timestamps
    end
    add_index :item_modifiers, :ingredient_ids, using: :gin
    add_index :item_modifiers, :tag_ids,        using: :gin

    create_table :item_ingredients, id: :uuid do |t|
      t.references :item,       type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.string :confidence, null: false, default: "suggested"
      t.string :source,     null: false, default: "human" # human | ai | owner
      t.timestamps
    end
    add_index :item_ingredients, [:item_id, :ingredient_id], unique: true

    create_table :item_tags, id: :uuid do |t|
      t.references :item, type: :uuid, null: false, foreign_key: true
      t.references :tag,  type: :uuid, null: false, foreign_key: true
      t.string :confidence, null: false, default: "suggested"
      t.string :source,     null: false, default: "human"
      t.timestamps
    end
    add_index :item_tags, [:item_id, :tag_id], unique: true
  end
end
