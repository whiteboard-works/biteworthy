class AddPositionToItems < ActiveRecord::Migration[7.1]
  def change
    add_column :items, :position, :integer, default: 0, null: false
    add_index :items, [:menu_section_id, :position]
  end
end
