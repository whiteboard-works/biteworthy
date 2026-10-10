# frozen_string_literal: true

# Failures the app reports — `Rails.error.report` from the chat loop, the
# tools, the controllers, and the unhandled exceptions Rails itself
# reports from requests and retried jobs — become GitHub issues: one per
# distinct failure, with a count, reopened when it comes back.
#
# Rails ships no subscriber of its own. Without this file every one of
# those `report` calls is a no-op, and the only trace of a failure is a
# log line on the box that nobody reads until a user writes in. ADR 0008
# has the pick; `ErrorReports::GithubIssues` has the behaviour.
#
# Subscribed in every environment: the subscriber only queues a job, and
# that job files nothing until `GITHUB_ERROR_REPORTS_TOKEN` is set.
Rails.application.config.after_initialize do
  Rails.error.subscribe(ErrorReports::Subscriber.new)
end
