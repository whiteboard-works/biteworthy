class CreateRestaurants < ActiveRecord::Migration
  def change
    create_table :restaurants do |t|
      t.string :name
      t.string :slogan
      t.string :main_image_url
      t.string :about
      t.string :disclaimer
      t.string :website
      t.integer :inside_seating
      t.integer :outside_seating
      t.boolean :cash_only
      t.boolean :delivers
      t.boolean :wifi
      t.boolean :active
      t.timestamps
    end
  end
end
