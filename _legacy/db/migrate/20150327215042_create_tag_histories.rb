class CreateTagHistories < ActiveRecord::Migration
  def change
    create_table :tag_histories do |t|
       t.string :tag_id
       t.string :name
       t.integer :created_by_id
       t.integer :last_modified_by_id
       t.timestamps
    end
  end
end
