class CreateExtrasFoods < ActiveRecord::Migration
  def change
    create_table :extras_foods do |t|
      t.integer :extra_id
      t.integer :food_id
    end
  end
end
