# frozen_string_literal: true

module DishPhotos
  # Creates a pending DishPhotoSubmission. The photo is rewritten
  # through Images::StripMetadata *before* attach, so the stored blob
  # never carries EXIF/GPS. Rate limits are application-level (not
  # Rack::Attack): 10 submissions per user per UTC day, 3 pending per
  # dish. A RateLimited error becomes 429 at the REST door.
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
      @owns_rights = ActiveModel::Type::Boolean.new.cast(owns_rights)
      @review = review
    end

    def call
      raise RateLimited.new(
        "You can submit at most #{DishPhotoSubmission::DAILY_LIMIT_PER_USER} dish photos per day.",
        code: "daily_limit"
      ) if over_daily_limit?

      raise RateLimited.new(
        "You already have #{DishPhotoSubmission::PENDING_PER_ITEM_LIMIT} photos of this dish waiting on a moderator.",
        code: "pending_limit"
      ) if over_pending_per_item_limit?

      unless photo_present?
        submission = DishPhotoSubmission.new
        submission.errors.add(:photo, "must be attached")
        raise ActiveRecord::RecordInvalid, submission
      end

      unless @owns_rights
        submission = DishPhotoSubmission.new
        submission.errors.add(:owns_rights, "must be accepted — you have to confirm you took this photo")
        raise ActiveRecord::RecordInvalid, submission
      end

      stripped = strip_photo
      DishPhotoSubmission.create!(
        item: @item,
        user: @user,
        review: @review,
        owns_rights: true,
        credit_name: credit_name,
        status: "pending"
      ) do |row|
        row.photo.attach(
          io: stripped.io,
          filename: stripped.filename,
          content_type: stripped.content_type
        )
      end
    end

    private

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
      if @photo.respond_to?(:original_filename)
        [ @photo.original_filename.presence || "dish.jpg", @photo.content_type ]
      elsif @photo.respond_to?(:filename)
        [ @photo.filename.to_s, @photo.content_type ]
      else
        [ "dish.jpg", "image/jpeg" ]
      end
    end

    def credit_name
      @user.display_name.presence || @user.handle.presence || "a diner"
    end
  end
end
