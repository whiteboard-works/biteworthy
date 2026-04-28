class CreateItemsIngredients < ActiveRecord::Migration
  def change
    create_table :items_ingredients do |t|
      t.integer :item_id
      t.integer :ingredient_id
    end
  end
end
