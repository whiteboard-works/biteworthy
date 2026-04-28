class AddParentIdToIngredient < ActiveRecord::Migration
  def change
    add_column :ingredients, :parent_id, :integer, after: :user_id
  end
end
