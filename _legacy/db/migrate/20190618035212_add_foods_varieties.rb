class AddFoodsVarieties < ActiveRecord::Migration
  def change
    create_table :foods_varieties do |t|
      t.integer  :food_id
      t.integer  :variety_id
     t.timestamps
    end

  end
end
