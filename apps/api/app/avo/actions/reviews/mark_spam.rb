class Avo::Actions::Reviews::MarkSpam < Avo::BaseAction
  self.name = "Mark spam → hide with reason 'spam'"
  self.message = "Hide the selected review(s) and tag them as spam in the audit log."
  self.confirm_button_label = "Mark spam"

  def handle(query:, **)
    hidden, skipped = Avo::Actions::Reviews::Hide.hide_all(query, reason: "spam")
    msg = +"Marked #{hidden} review(s) as spam."
    msg << " Skipped #{skipped} already-hidden." if skipped.positive?
    succeed msg
  end
end
