class AddIngredientFirstToVarieties < ActiveRecord::Migration
  def change
    add_column :varieties, :ingredient_first, :boolean, default: false, after: :ingredient_id
  end
end
