class CreateMenuGroupsTags < ActiveRecord::Migration
  def change
    create_table :menu_groups_tags do |t|
       t.integer :menu_group_id
       t.integer :tag_id
    end
  end
end
