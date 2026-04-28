class CreateAddresses < ActiveRecord::Migration
  def change
    create_table :addresses do |t|
      t.integer :restaurant_id
      t.string :phone_number
      t.string :street
      t.string :city, default: "Durango"
      t.string :state, default: "CO"
      t.integer :zip, default: 81301
      t.string  :place_id
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
    end
  end
end
