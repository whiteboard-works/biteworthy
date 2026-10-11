# frozen_string_literal: true

module DishPhotos
  # Creates a DishPhotoSubmission, pending unless an admin uploaded it. The photo is rewritten
  # through Images::StripMetadata *before* attach, so the stored blob
  # never carries EXIF/GPS. Rate limits are application-level (not
  # Rack::Attack): 10 submissions per user per UTC day (including
  # withdrawn ones), 3 pending per dish. A RateLimited error becomes
  # 429 at the REST door.
  #
  # Count-and-create runs under a per-user advisory lock so two
  # concurrent uploads cannot both observe "9 today" and both commit.
  #
  # An admin's upload skips the daily limit and is approved straight
  # onto the dish as its photo. If that approve fails the row stays
  # pending for /admin/photos, so the per-dish pending limit still holds.
  class Submit
    class RateLimited < StandardError
      attr_reader :code

      def initialize(message, code:)
        super(message)
        @code = code
      end
    end

    def self.call(item:, user:, photo:, owns_rights:, review: nil)
      new(item:, user:, photo:, owns_rights:, review:).call
    end

    def self.from_review(review, owns_rights:)
      raise ArgumentError, "review has no photo" unless review.photo.attached?

      call(
        item: review.item,
        user: review.user,
        photo: review.photo,
        owns_rights:,
        review:
      )
    end

    def initialize(item:, user:, photo:, owns_rights:, review: nil)
      @item = item
      @user = user
      @photo = photo
      @owns_rights = owns_rights
      @review = review
    end

    def call
      unless DishPhotos::OwnsRights.accepted?(@owns_rights)
        submission = DishPhotoSubmission.new
        submission.errors.add(:owns_rights, "must be accepted — you have to confirm you took this photo")
        raise ActiveRecord::RecordInvalid, submission
      end

      unless photo_present?
        submission = DishPhotoSubmission.new
        submission.errors.add(:photo, "must be attached")
        raise ActiveRecord::RecordInvalid, submission
      end

      existing = submission_from_same_upload
      return existing if existing

      # Bound + strip before the lock so a decompression bomb does not
      # hold the user's submission lock.
      stripped = strip_photo

      submission = DishPhotoSubmission.transaction do
        lock_user!
        existing = submission_from_same_upload
        return existing if existing

        enforce_daily_limit! unless @user.is_admin?
        enforce_pending_limit!

        DishPhotoSubmission.create!(
          item: @item,
          user: @user,
          review: @review,
          owns_rights: true,
          credit_name: credit_name,
          status: "pending",
          source_upload_id: source_upload_id
        ) do |row|
          row.photo.attach(
            io: stripped.io,
            filename: stripped.filename,
            content_type: stripped.content_type
          )
        end
      end

      auto_approve(submission) if @user.is_admin?
      submission
    end

    private

    # Runs after commit: Moderate re-locks the item then the submission,
    # and copies the blob outside any lock.
    def auto_approve(submission)
      DishPhotos::Moderate.new(submission, reviewer: @user).approve!(replace_item_photo: true)
    rescue StandardError => e
      Rails.logger.warn("Admin dish-photo auto-approve failed for #{submission.id}: #{e.class} #{e.message}")
      submission.reload
    end

    def enforce_daily_limit!
      raise RateLimited.new(
        "You can submit at most #{DishPhotoSubmission::DAILY_LIMIT_PER_USER} dish photos per day.",
        code: "daily_limit"
      ) if over_daily_limit?
    end

    def enforce_pending_limit!
      raise RateLimited.new(
        "You already have #{DishPhotoSubmission::PENDING_PER_ITEM_LIMIT} photos of this dish waiting on a moderator.",
        code: "pending_limit"
      ) if over_pending_per_item_limit?
    end

    def lock_user!
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          [ "SELECT pg_advisory_xact_lock(hashtext(?))", "dish-photo-submit:#{@user.id}" ]
        )
      )
    end

    # A signed upload (the chat tool's door) records which blob it came
    # from, so replaying the same confirmed call returns the submission
    # it already made — whatever has happened to it since — instead of
    # queueing the photo again. A withdrawn or rejected photo does not
    # come back on a stale yes.
    def source_upload_id
      @photo.id if @photo.is_a?(ActiveStorage::Blob)
    end

    def submission_from_same_upload
      return nil unless source_upload_id

      DishPhotoSubmission.find_by(user_id: @user.id, item_id: @item.id, source_upload_id:)
    end

    def over_daily_limit?
      DishPhotoSubmission.where(user_id: @user.id)
                         .where("created_at >= ?", Time.current.utc.beginning_of_day)
                         .count >= DishPhotoSubmission::DAILY_LIMIT_PER_USER
    end

    def over_pending_per_item_limit?
      DishPhotoSubmission.pending.where(item_id: @item.id, user_id: @user.id)
                         .count >= DishPhotoSubmission::PENDING_PER_ITEM_LIMIT
    end

    def photo_present?
      if @photo.respond_to?(:attached?)
        @photo.attached?
      elsif @photo.is_a?(ActiveStorage::Blob)
        true
      elsif @photo.respond_to?(:tempfile)
        true
      elsif @photo.respond_to?(:read)
        true
      else
        false
      end
    end

    def strip_photo
      filename, content_type = source_identity
      Images::StripMetadata.call(@photo, filename:, content_type:)
    end

    def source_identity
      ident = Images::AttachPhoto.identity(@photo)
      [ ident[:filename], ident[:content_type] ]
    end

    def credit_name
      @user.display_name.presence || @user.handle.presence || DishPhotoSubmission::ANONYMOUS_CREDIT
    end
  end
end
