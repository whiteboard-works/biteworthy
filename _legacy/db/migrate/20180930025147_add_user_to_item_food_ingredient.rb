class AddUserToItemFoodIngredient < ActiveRecord::Migration
  def change
    add_column :items, :user_id, :integer, after: :description
    add_column :foods, :user_id, :integer, after: :description
    add_column :tags, :user_id, :integer, after: :variety
    add_column :ingredients, :user_id, :integer, after: :normalized_name
  end
end
