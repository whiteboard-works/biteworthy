class RemoveFoodIdFromVarieties < ActiveRecord::Migration
  def change
    remove_column :varieties, :food_id, :integer
  end
end
