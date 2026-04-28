class AddParentIdToTag < ActiveRecord::Migration
  def up
    add_column :tags, :parent_id, :integer, after: :user_id
    drop_table :tags_families
    drop_table :tags_groups_relations
  end
  def down
    remove_column :tags, :parent_id
  end
end
