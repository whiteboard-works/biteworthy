# frozen_string_literal: true

module Tools
  module Reviews
    class EditReview < Reviews::Base
      audience :user

      tool_name "edit_review"
      title "Edit one of the caller's reviews"
      description <<~TEXT
        Change the rating or body of a review the caller wrote. Omitted fields
        are left alone. Only the author can edit; anyone else gets `forbidden`.

        Get the review id from `list_reviews`. Editing the body re-runs the
        moderation heuristic, so a previously clean review can become flagged.
      TEXT

      input_schema(
        properties: {
          review_id: { type: "string", description: "The review's UUID." },
          rating:    { type: "integer", description: "New rating, 1 to 5.", minimum: 1, maximum: 5 },
          body:      { type: "string", description: "New body. Pass an empty string to clear it." }
        },
        required: ["review_id"]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      def self.perform(context:, review_id:, rating: nil, body: nil)
        review = find_review!(review_id)
        authorize_author!(context, review)

        attrs = {}
        attrs[:rating] = rating unless rating.nil?
        attrs[:body]   = body   unless body.nil?
        raise Errors::InvalidArgument, "Pass rating, body, or both." if attrs.empty?

        review.update!(attrs)
        ok(review_row(review).merge(flagged_for_moderation: review.flagged?))
      end
    end
  end
end
