class CreateIngredientsTags < ActiveRecord::Migration
  def change
    create_table :ingredients_tags do |t|
       t.integer :ingredient_id
       t.integer :tag_id
    end
  end
end
