class CreateTagsFamilies < ActiveRecord::Migration
  def change
     create_table :tags_families do |t|
       t.integer  :parent_tag_id
       t.integer  :child_tag_id
       t.timestamps

    end
  end
end
