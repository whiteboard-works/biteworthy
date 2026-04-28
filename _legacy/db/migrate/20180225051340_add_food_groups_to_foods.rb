class AddFoodGroupsToFoods < ActiveRecord::Migration
  def change
    add_column :foods, :food_group, :integer
  end
end
