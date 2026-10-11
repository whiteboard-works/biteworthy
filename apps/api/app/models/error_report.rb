# frozen_string_literal: true

# One row per distinct failure the app has reported, and the bridge
# between `Rails.error` and the GitHub issue that tracks it.
#
# `fingerprint` is what makes two failures "the same one": the error
# class, the message with ids and numbers blanked, and the first app
# frame without its line number (`ErrorReports::Capture`). Everything
# that recurs lands on one row, and the row knows which issue it already
# has — so a bug that fires a thousand times is one issue with a count,
# not a thousand issues.
class ErrorReport < ApplicationRecord
  # Counts the occurrences a payload carries (one, or a throttled
  # burst's worth), keeping the details from the first one.
  #
  # One statement, so two workers recording the same fingerprint at the
  # same moment both count: a find-then-create would have one of them
  # lose on the unique index and drop its occurrences.
  def self.record!(payload)
    now   = Time.current
    count = Integer(payload.fetch("occurrences", 1))
    upsert(
      {
        fingerprint:   payload.fetch("fingerprint"),
        error_class:   payload.fetch("error_class"),
        title:         payload.fetch("title"),
        message:       payload.fetch("message"),
        source:        payload.fetch("source"),
        handled:       payload.fetch("handled"),
        context:       payload.fetch("context"),
        backtrace:     payload["backtrace"],
        occurrences:   count,
        first_seen_at: now,
        last_seen_at:  now,
        created_at:    now,
        updated_at:    now
      },
      unique_by: :fingerprint,
      on_duplicate: Arel.sql(
        "occurrences = error_reports.occurrences + EXCLUDED.occurrences, " \
        "last_seen_at = EXCLUDED.last_seen_at, updated_at = EXCLUDED.updated_at"
      )
    )
    find_by!(fingerprint: payload.fetch("fingerprint"))
  end

  # Occurrences the issue has not been told about yet.
  def unreported? = occurrences > issue_occurrences

  # Takes the right to write to the issue, at most once per `interval`.
  #
  # A conditional UPDATE rather than a row lock, so the HTTP call that
  # follows never runs inside one. A second worker arriving in the same
  # window finds the slot taken and leaves — the count on the row speaks
  # for it at the next write.
  def claim_issue_slot!(interval:)
    now  = Time.current
    rows = self.class.where(id: id)
                     .where("issue_touched_at IS NULL OR issue_touched_at < ?", now - interval)
                     .update_all(issue_touched_at: now, updated_at: now)
    self.issue_touched_at = now if rows == 1
    rows == 1
  end

  # Gives a claimed slot back, so a write that failed is tried again on
  # the next occurrence rather than an hour later.
  def release_issue_slot!(to:)
    self.class.where(id: id, issue_touched_at: issue_touched_at).update_all(issue_touched_at: to)
    self.issue_touched_at = to
  end

  # Books one catch-up sync for when the slot frees, and only one: a
  # burst inside the window would otherwise book a job per occurrence.
  # Returns true for the caller that should enqueue it.
  def schedule_sync!(at:)
    rows = self.class.where(id: id)
                     .where("sync_scheduled_at IS NULL OR sync_scheduled_at < ?", Time.current)
                     .update_all(sync_scheduled_at: at)
    self.sync_scheduled_at = at if rows == 1
    rows == 1
  end
end
