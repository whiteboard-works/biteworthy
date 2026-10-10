# frozen_string_literal: true

module ErrorReports
  # Records the occurrences and brings their GitHub issue up to date. Runs
  # off the failing code path, so the HTTP call costs the request or turn
  # that failed nothing.
  #
  # Never raises past `perform`: a raise would reach `ApplicationJob`'s
  # retry, a retry would count the occurrences twice, and an exception
  # from the error reporter is the one kind nothing can report. A GitHub
  # blip after the row is recorded is handed to `SyncIssueJob` instead,
  # which retries freely because it only syncs — so a one-off failure
  # still gets its issue even if it never recurs.
  class FileIssueJob < ApplicationJob
    queue_as :default
    # Behind everything else on the queue. A failure that fires on every
    # request would otherwise queue a report per request ahead of the
    # chat turns and menu scans those requests were about — Solid Queue
    # runs the lowest number first, and 0 is the default.
    queue_with_priority 100

    def perform(payload)
      report = ErrorReport.record!(payload)
      GithubIssues.new.sync(report) if GithubIssues.configured?
    rescue StandardError => e
      Rails.logger.warn(
        "[error_reports] #{payload['fingerprint']} could not be filed: #{e.class}: #{e.message}"
      )
      SyncIssueJob.perform_later(report.id) if report
    end
  end
end
