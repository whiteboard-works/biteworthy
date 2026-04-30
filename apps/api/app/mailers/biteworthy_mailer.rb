# frozen_string_literal: true

# Phase 5.2 — generic mailer for the production SMTP smoke task.
#
# Sends a single self-contained message that proves the wiring works
# end-to-end: ActionMailer → ApplicationMailer layout → SMTP →
# inbox. Doesn't depend on any database record, so the smoke task
# can run on a fresh deploy before there are users / restaurants /
# suggestions.
class BiteworthyMailer < ApplicationMailer
  def smoke_test(to:)
    @sent_at = Time.current.utc
    mail(
      to:      to,
      subject: "BiteWorthy SMTP smoke test (#{@sent_at.iso8601})"
    )
  end
end
