# frozen_string_literal: true

module ErrorReports
  # The catch-up for occurrences that arrived while the hourly write slot
  # was taken. Without it, an issue closed at noon that recurs once at
  # ten past stays closed: the recurrence found the slot busy, and
  # nothing later would have looked again.
  #
  # Unlike `FileIssueJob` this one *does* raise, so `ApplicationJob`'s
  # retry gets another go at a GitHub blip. That is safe here because
  # the row already holds the count — a retry syncs, it never records —
  # and it matters because this job may be the only chance a lone
  # recurrence gets. `Subscriber` ignores failures from every
  # `ErrorReports::` job, so an exhausted retry cannot report itself.
  class SyncIssueJob < ApplicationJob
    queue_as :default
    queue_with_priority 100

    def perform(report_id)
      report = ErrorReport.find_by(id: report_id)
      return if report.nil? || !report.unreported?

      GithubIssues.new.sync(report) if GithubIssues.configured?
    end
  end
end
