# Phase 4.9 — emails the verification link to the restaurant owner.
#
# Production: real SMTP. The Phase 4 stop condition (no SMTP creds in
# CI/dev yet) means this mailer's `:test` adapter captures the
# message in specs and the dev environment logs the verify URL to
# Rails.logger so the demo works without an inbox.
class RestaurantClaimMailer < ApplicationMailer
  def verify_email(suggestion_id, verify_url)
    @suggestion = Suggestion.find(suggestion_id)
    @restaurant = @suggestion.subject
    @verify_url = verify_url

    mail(
      to: @suggestion.payload["email"],
      subject: "Verify your claim on #{@restaurant.name}"
    )

    # Phase 4 stop-condition fallback: if SMTP isn't configured, the
    # dev-mode workflow needs the link somewhere reachable. Logging
    # it satisfies the demo path without exposing it in production.
    if Rails.env.development?
      Rails.logger.info("[RestaurantClaimMailer] verify URL for #{@restaurant.name}: #{verify_url}")
    end
  end
end
