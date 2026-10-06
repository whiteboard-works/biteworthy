# frozen_string_literal: true

# Withdrawals must keep counting toward the daily limit, so they become
# a status rather than a hard delete. approve_keep is distinct from
# approved so account deletion can drop uncredited photos while keeping
# an approved-and-set dish photo.
class WidenDishPhotoSubmissionStatuses < ActiveRecord::Migration[8.1]
  NEW_STATUSES = %w[pending approved rejected withdrawn approve_keep].freeze
  OLD_STATUSES = %w[pending approved rejected].freeze

  def up
    remove_check_constraint :dish_photo_submissions, name: "dish_photo_submissions_status_valid"
    add_check_constraint :dish_photo_submissions,
                         "status IN (#{NEW_STATUSES.map { |v| "'#{v}'" }.join(', ')})",
                         name: "dish_photo_submissions_status_valid"
  end

  def down
    execute <<~SQL.squish
      UPDATE dish_photo_submissions SET status = 'rejected'
      WHERE status IN ('withdrawn', 'approve_keep')
    SQL
    remove_check_constraint :dish_photo_submissions, name: "dish_photo_submissions_status_valid"
    add_check_constraint :dish_photo_submissions,
                         "status IN (#{OLD_STATUSES.map { |v| "'#{v}'" }.join(', ')})",
                         name: "dish_photo_submissions_status_valid"
  end
end
