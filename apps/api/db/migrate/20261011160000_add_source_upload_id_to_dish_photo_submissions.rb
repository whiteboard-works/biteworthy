# frozen_string_literal: true

# The POST /attachments blob a chat submission was made from, so replaying
# the same confirmed `submit_dish_photo` returns the row it already made.
# A column rather than blob metadata because withdraw and reject purge the
# stored photo, and with it anything recorded on it. No foreign key: the
# upload itself is purged within a day (PurgeUnscannedAttachmentsJob).
class AddSourceUploadIdToDishPhotoSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :dish_photo_submissions, :source_upload_id, :bigint
    add_index :dish_photo_submissions, %i[user_id item_id source_upload_id],
              unique: true, where: "source_upload_id IS NOT NULL",
              name: "index_dish_photo_submissions_on_source_upload"
  end
end
