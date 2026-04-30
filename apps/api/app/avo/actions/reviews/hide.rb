class Avo::Actions::Reviews::Hide < Avo::BaseAction
  self.name = "Hide → remove from public feed"
  self.message = "Hide the selected review(s) from the public feed? Pick a reason for the audit log."
  self.confirm_button_label = "Hide"

  def fields
    field :reason, as: :select,
          options: Review::HIDDEN_REASONS.index_with(&:itself),
          required: true,
          default: "off_topic",
          help: "Recorded so we can audit moderation later."
  end

  def handle(query:, fields:, **)
    reason = (fields[:reason].presence || "off_topic")
    hidden, skipped = self.class.hide_all(query, reason: reason)
    msg = +"Hid #{hidden} review(s)."
    msg << " Skipped #{skipped} already-hidden." if skipped.positive?
    succeed msg
  end

  # Pure logic; reusable by specs without going through Avo's
  # controller lifecycle (which wires up #succeed). Same pattern as
  # Phase 2.5's IngestionItems::Accept.
  def self.hide_all(reviews, reason:)
    hidden  = 0
    skipped = 0
    reviews.each do |review|
      if review.hidden?
        skipped += 1
        next
      end
      review.hide!(reason: reason)
      hidden += 1
    end
    [hidden, skipped]
  end
end
