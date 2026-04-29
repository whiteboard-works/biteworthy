class ApplicationJob < ActiveJob::Base
  # Phase 2 jobs run on Solid Queue (configured in application.rb).
  # Reserve the default retry strategy: keep network/transient errors
  # in flight for a few attempts, but bail out on validation errors.
  retry_on StandardError, attempts: 3, wait: :polynomially_longer
  discard_on ActiveJob::DeserializationError
end
