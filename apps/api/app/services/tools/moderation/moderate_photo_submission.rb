# frozen_string_literal: true

module Tools
  module Moderation
    class ModeratePhotoSubmission < Tools::AdminBase
      tool_name "moderate_photo_submission"
      title "Approve or reject a diner dish photo"
      description <<~TEXT
        Decide a pending diner photo of a dish. `approve_and_set` copies it
        onto the dish as the public photo (and attributes it to the diner).
        `approve_keep` marks it approved without replacing a photo the dish
        already has. `reject` needs a reason.

        Look at the photo before approving. A submission for the wrong dish,
        a screenshot, or anything that is not food should be rejected, not
        set as the dish photo.

        Approving is not reversible through this tool: a later staff upload
        or another approve_and_set replaces the dish photo.
      TEXT

      ACTIONS = %w[approve_and_set approve_keep reject].freeze

      input_schema(
        properties: {
          photo_submission_id: {
            type: "string",
            description: "The submission UUID, from list_photo_submissions."
          },
          action: {
            type: "string",
            description: "What to do.",
            enum: ACTIONS
          },
          reason: {
            type: "string",
            description: "Required when rejecting.",
            enum: DishPhotoSubmission::REJECTION_REASONS
          }
        },
        required: %w[photo_submission_id action]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      running_description { "Moderating the dish photo" }

      unrecoverable_when { |args| args[:action].to_s.start_with?("approve") }

      def self.perform(context:, photo_submission_id:, action:, reason: nil)
        context.admin!
        unless ACTIONS.include?(action)
          raise Errors::InvalidArgument, "action must be one of: #{ACTIONS.join(', ')}."
        end

        submission = DishPhotoSubmission.includes(:item, :user, photo_attachment: :blob)
                                        .find(photo_submission_id)
        moderator = DishPhotos::Moderate.new(submission, reviewer: context.user)

        case action
        when "approve_and_set"
          moderator.approve!(replace_item_photo: true)
        when "approve_keep"
          moderator.approve!(replace_item_photo: false)
        else
          begin
            moderator.reject!(reason: reason)
          rescue DishPhotos::Moderate::InvalidReason
            raise Errors::InvalidArgument,
                  "reason must be one of: #{DishPhotoSubmission::REJECTION_REASONS.join(', ')}."
          end
        end

        ok(
          photo_submission_id: submission.id,
          status: submission.status,
          rejection_reason: submission.rejection_reason,
          item_id: submission.item_id,
          replace_item_photo: action == "approve_and_set"
        )
      rescue DishPhotos::Moderate::NotPending => e
        raise Errors::InvalidArgument, e.message
      end
    end
  end
end
