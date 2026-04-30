class Avo::Actions::Reviews::Unhide < Avo::BaseAction
  self.name = "Unhide → restore to public feed"
  self.message = "Restore the selected review(s) to the public feed and clear the moderation flag."
  self.confirm_button_label = "Unhide"

  def handle(query:, **)
    restored, skipped = self.class.unhide_all(query)
    msg = +"Restored #{restored} review(s)."
    msg << " Skipped #{skipped} already-visible." if skipped.positive?
    succeed msg
  end

  def self.unhide_all(reviews)
    restored = 0
    skipped  = 0
    reviews.each do |review|
      if !review.hidden? && !review.flagged?
        skipped += 1
        next
      end
      review.unhide!
      restored += 1
    end
    [restored, skipped]
  end
end
