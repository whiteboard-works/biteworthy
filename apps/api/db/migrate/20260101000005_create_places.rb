class CreatePlaces < ActiveRecord::Migration[8.0]
  def change
    create_table :cities, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :region                  # state / province
      t.string :country, null: false, default: "US"
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.timestamps
    end
    add_index :cities, :slug, unique: true

    create_table :restaurants, id: :uuid do |t|
      t.references :city, type: :uuid, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.text   :about
      t.string :website
      t.string :phone
      t.string :status, null: false, default: "draft" # draft | published | closed
      t.references :claimed_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :claimed_at
      t.timestamps
    end
    add_index :restaurants, :slug, unique: true
    add_index :restaurants, [:city_id, :status]

    create_table :addresses, id: :uuid do |t|
      t.references :restaurant, type: :uuid, null: false, foreign_key: true
      t.string  :street
      t.string  :city
      t.string  :region
      t.string  :postal_code
      t.string  :country, default: "US"
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.string  :map_provider_place_id
      t.timestamps
    end

    create_table :hours, id: :uuid do |t|
      t.references :restaurant, type: :uuid, null: false, foreign_key: true
      t.integer :day_of_week, null: false # 0 = Sunday
      t.time :opens_at
      t.time :closes_at
      t.timestamps
    end
    add_index :hours, [:restaurant_id, :day_of_week]
  end
end
