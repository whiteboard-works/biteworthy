class CreateRoles < ActiveRecord::Migration
  def change
    create_table :roles do |t|
      t.integer :role_type
      t.string :name
      t.string :description
      t.timestamps
    end
  end
end
