class CreateVarieties < ActiveRecord::Migration
  def change
    create_table :varieties do |t|
      t.string :name
      t.integer :food_id
      t.integer :ingredient_id

      t.timestamps null: false
    end
  end
end
