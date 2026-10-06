# frozen_string_literal: true

# Diner-submitted dish photos wait in a moderation queue before they
# become Item#photo. The join is the source of attribution ("Photo by …")
# on the dish page: items.photo_submission_id points at the approved row
# that supplied the current image. Admin PATCH still attaches through
# ItemEditor and clears that pointer so a staff upload is not credited
# to a diner.
class CreateDishPhotoSubmissions < ActiveRecord::Migration[8.1]
  STATUSES = %w[pending approved rejected].freeze
  REJECTION_REASONS = %w[not_this_dish low_quality inappropriate not_food duplicate].freeze

  def change
    create_table :dish_photo_submissions, id: :uuid do |t|
      t.references :item, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :review, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.string :rejection_reason
      t.references :reviewed_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.boolean :owns_rights, null: false, default: false
      t.string :credit_name, null: false
      t.timestamps
    end

    add_index :dish_photo_submissions, :status
    add_index :dish_photo_submissions, [ :item_id, :status ]
    add_index :dish_photo_submissions, [ :user_id, :created_at ]

    add_check_constraint :dish_photo_submissions,
                         "status IN (#{STATUSES.map { |v| "'#{v}'" }.join(', ')})",
                         name: "dish_photo_submissions_status_valid"
    add_check_constraint :dish_photo_submissions,
                         "rejection_reason IS NULL OR rejection_reason IN (#{REJECTION_REASONS.map { |v| "'#{v}'" }.join(', ')})",
                         name: "dish_photo_submissions_rejection_reason_valid"

    add_reference :items, :photo_submission, type: :uuid,
                  foreign_key: { to_table: :dish_photo_submissions, on_delete: :nullify }
  end
end
