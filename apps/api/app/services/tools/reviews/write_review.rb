# frozen_string_literal: true

module Tools
  module Reviews
    class WriteReview < Reviews::Base
      audience :user

      tool_name "write_review"
      title "Review a dish"
      description <<~TEXT
        Record the caller's own rating of a dish, 1 to 5, with an optional
        note. Take the dish id from `get_menu` or `explain_item`.

        Write what the user actually said. Do not invent a rating they did not
        give, do not soften a complaint, and do not review on their behalf
        without being asked to.

        A review is public and attributed to their handle. Bodies containing
        links or slurs are auto-flagged for a moderator; that is expected and
        does not hide the review.

        One review per person per dish. If they already reviewed it, this
        fails and tells you the id — change it with `edit_review` rather than
        replacing what they wrote.
      TEXT

      input_schema(
        properties: {
          item_id: { type: "string", description: "The dish's UUID." },
          rating:  { type: "integer", description: "1 (worst) to 5 (best).", minimum: 1, maximum: 5 },
          body:    { type: "string", description: "Optional free text, in the user's own words." }
        },
        required: %w[item_id rating]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)

      running_description { "Posting your review" }

      def self.perform(context:, item_id:, rating:, body: nil)
        user = context.user!
        item = Item.published.joins(:restaurant).merge(Restaurant.published).find(item_id)

        # The DB enforces one review per (user, dish). Reporting the clash as
        # a recoverable error beats overwriting: the model can route to
        # edit_review, and nobody's words vanish because a turn repeated.
        existing = Review.find_by(user_id: user.id, item_id: item.id)
        if existing
          raise Errors::InvalidArgument,
                "You already reviewed this dish (review #{existing.id}). Use edit_review to change it."
        end

        review = Review.create!(user: user, item: item, rating: rating, body: body)
        ok(review_row(review).merge(flagged_for_moderation: review.flagged?))
      end
    end
  end
end
