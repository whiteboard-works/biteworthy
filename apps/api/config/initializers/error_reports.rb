# frozen_string_literal: true

# Failures the app reports — `Rails.error.report` from the chat loop, the
# tools, the controllers, the unhandled exceptions Rails reports from
# requests, and the job failures `ApplicationJob` reports once its retries
# are spent — become GitHub issues: one per distinct failure, with a
# count, reopened when it comes back.
#
# Without this file every one of those `report` calls makes a PostHog
# event (ADR 0009) and nothing else, and no failure has one place where
# its count and its fix's PR meet. ADR 0008 has the pick;
# `ErrorReports::GithubIssues` has the behaviour.
#
# Subscribed in every environment: the subscriber only queues a job, and
# that job files nothing until `GITHUB_ERROR_REPORTS_TOKEN` is set.
Rails.application.config.after_initialize do
  Rails.error.subscribe(ErrorReports::Subscriber.new)

  # Mail goes through Action Mailer's own job, which is not an
  # `ApplicationJob` and does not retry; its handler re-raises when the
  # mailer has no rescue of its own, which never reaches `after_discard`.
  # No mailer here declares one, so reporting first changes nothing else.
  ActionMailer::MailDeliveryJob.rescue_from(Exception) do |error|
    Rails.error.report(error, handled: false, source: "application.active_job")
    raise error
  end
end
