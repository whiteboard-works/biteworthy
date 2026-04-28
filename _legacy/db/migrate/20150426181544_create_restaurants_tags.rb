class CreateRestaurantsTags < ActiveRecord::Migration
  def change
    create_table :restaurants_tags do |t|
       t.integer :restaurant_id
       t.integer :tag_id
    end
  end
end
