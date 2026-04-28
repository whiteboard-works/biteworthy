class AddTagsToExtras < ActiveRecord::Migration
  def change
    create_table :extras_tags do |t|
      t.integer :extra_id
      t.integer :tag_id
    end
  end
end
