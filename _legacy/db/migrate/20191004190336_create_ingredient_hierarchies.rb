class CreateIngredientHierarchies < ActiveRecord::Migration
  def change
    create_table :ingredient_hierarchies, id: false do |t|
      t.integer :ancestor_id, null: false
      t.integer :descendant_id, null: false
      t.integer :generations, null: false
    end

    add_index :ingredient_hierarchies, [:ancestor_id, :descendant_id, :generations],
      unique: true,
      name: "ingredient_anc_desc_idx"

    add_index :ingredient_hierarchies, [:descendant_id],
      name: "ingredient_desc_idx"
  end
end
