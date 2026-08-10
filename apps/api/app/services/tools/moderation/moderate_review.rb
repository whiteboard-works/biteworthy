# frozen_string_literal: true

module Tools
  module Moderation
    class ModerateReview < Tools::AdminBase
      tool_name "moderate_review"
      title "Hide or restore a review"
      description <<~TEXT
        Take a review out of the public feed, or put it back. Hiding needs a
        reason, which is recorded and shown to the review's author — they can
        still see their own hidden review and why it went.

        Hiding is not deleting. The review survives for the audit trail, and
        `unhide` reverses it. Only the author can actually delete a review.

        Do not hide a review for being negative or wrong about a dish. The
        reasons are what they say: spam, abuse, a duplicate, or off topic.
      TEXT

      ACTIONS = %w[hide unhide].freeze

      input_schema(
        properties: {
          review_id: { type: "string", description: "The review's UUID, from list_moderation_queue." },
          action:    { type: "string", description: "What to do.", enum: ACTIONS },
          reason:    { type: "string", description: "Required when hiding.", enum: Review::HIDDEN_REASONS }
        },
        required: %w[review_id action]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      # Hiding and unhiding are the same call with a different argument.
      unrecoverable_when { false }

      def self.perform(context:, review_id:, action:, reason: nil)
        context.admin!
        raise Errors::InvalidArgument, "action must be one of: #{ACTIONS.join(', ')}." unless ACTIONS.include?(action)

        review = Review.includes(:user, item: :restaurant).find(review_id)

        if action == "hide"
          unless Review::HIDDEN_REASONS.include?(reason)
            raise Errors::InvalidArgument, "reason must be one of: #{Review::HIDDEN_REASONS.join(', ')}."
          end

          review.hide!(reason: reason)
        else
          review.unhide!
        end

        ok(
          review_id:     review.id,
          hidden:        review.hidden?,
          hidden_reason: review.hidden_reason,
          author:        review.user.handle
        )
      end
    end
  end
end
