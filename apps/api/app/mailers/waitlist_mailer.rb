# frozen_string_literal: true

# Phase 5.10 — confirmation mailer for soft-launch waitlist signups.
#
# Fires once per signup. Goes through the Phase 5.2 SMTP pipeline
# (production: Postmark; dev/test: :test adapter so deliveries land
# in ActionMailer::Base.deliveries for inspection).
#
# Informational, not a double-opt-in gate. The signup is already on
# the list when this mail fires.
class WaitlistMailer < ApplicationMailer
  def confirm(signup_id)
    @signup = WaitlistSignup.find(signup_id)
    mail(
      to:      @signup.email,
      subject: "You're on the BiteWorthy waitlist"
    )
  end
end
