class CreateMenuGroups < ActiveRecord::Migration
  def change
    create_table :menu_groups do |t|
      t.integer :restaurant_id
      t.integer :menu_order, default: 1
      t.string  :name
      t.string  :description
      t.timestamps
    end
  end
end
