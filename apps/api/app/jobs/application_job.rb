class ApplicationJob < ActiveJob::Base
  # Phase 2 jobs run on Solid Queue (configured in application.rb).
  # Reserve the default retry strategy: keep network/transient errors
  # in flight for a few attempts, but bail out on validation errors.
  RETRY_ATTEMPTS = 3
  retry_on StandardError, attempts: RETRY_ATTEMPTS, wait: :polynomially_longer
  discard_on ActiveJob::DeserializationError

  # Solid Queue never hands a job's final exception to `Rails.error`: its
  # `ClaimedExecution#execute` rescues it inside the app executor and
  # files a failed execution instead. So the job reports it, here, once —
  # `after_discard` runs when `retry_on` gives up and when an exception
  # nothing handles escapes, never on an attempt that will be retried.
  # A deserialization discard is a job for a row that is gone, which is
  # the discard's point rather than a failure.
  after_discard do |_job, error|
    next if error.is_a?(ActiveJob::DeserializationError)

    Rails.error.report(error, handled: false, source: "application.active_job")
  end
end
