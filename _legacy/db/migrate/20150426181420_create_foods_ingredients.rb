class CreateFoodsIngredients < ActiveRecord::Migration
  def change
    create_table :foods_ingredients do |t|
      t.integer  :food_id
      t.integer  :ingredient_id
     t.timestamps
    end
  end
end
