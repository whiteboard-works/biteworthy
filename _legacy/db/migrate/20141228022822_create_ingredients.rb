class CreateIngredients < ActiveRecord::Migration
  def change
    create_table :ingredients do |t|
      t.string  :name
      t.string  :normalized_name
      t.timestamps
    end
  end
end
