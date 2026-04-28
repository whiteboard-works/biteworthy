class ChangeMenuGroupDescriptionToText < ActiveRecord::Migration
  def change
    change_column :menu_groups, :description, :text
  end
end
