class CreatePhotos < ActiveRecord::Migration
  def change
    create_table :photos do |t|
       t.string     :title
       t.string     :caption
       t.integer    :user_id
       t.integer    :photo_id
       t.string     :photo_type
       t.attachment :image
       t.integer    :image_type, default: 1
       t.timestamps
    end
  end
end
