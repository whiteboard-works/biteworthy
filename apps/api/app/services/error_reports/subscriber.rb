# frozen_string_literal: true

module ErrorReports
  # What `Rails.error.subscribe` is given. Hands the failure to a job and
  # gets out of the way: this runs inside whatever just failed — a turn,
  # a request, a worker thread — and may cost it one queue insert, never
  # an HTTP call and never a second exception.
  class Subscriber
    def report(error, handled:, severity:, context:, source:)
      # The jobs that file issues must never file issues about
      # themselves: a failure there would queue another copy of itself,
      # and so on until the queue held nothing else.
      return if context[:job].class.name.to_s.start_with?("ErrorReports::")

      payload = Capture.call(error, context: context, source: source, handled: handled)
      count   = Throttle.shared.admit(payload["fingerprint"])
      return if count.zero?

      FileIssueJob.perform_later(payload.merge("occurrences" => count))
    rescue StandardError => e
      Rails.logger.warn("[error_reports] could not queue #{error.class} (#{severity}): #{e.class}: #{e.message}")
    end
  end
end
