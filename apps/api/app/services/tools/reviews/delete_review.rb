# frozen_string_literal: true

module Tools
  module Reviews
    class DeleteReview < Reviews::Base
      audience :user

      tool_name "delete_review"
      title "Delete one of the caller's reviews"
      description <<~TEXT
        Permanently remove a review the caller wrote. Only the author can
        delete. There is no undo — confirm with the user before calling, and
        never delete a review as a side effect of another request.

        To take a review out of the public feed without destroying it, an
        admin hides it instead (`moderate_review`).
      TEXT

      input_schema(
        properties: {
          review_id: { type: "string", description: "The review's UUID." }
        },
        required: ["review_id"]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

      def self.perform(context:, review_id:)
        review = find_review!(review_id)
        authorize_author!(context, review)
        review.destroy!

        ok(deleted: true, review_id: review_id)
      end
    end
  end
end
