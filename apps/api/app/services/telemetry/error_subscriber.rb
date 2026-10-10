# frozen_string_literal: true

module Telemetry
  # The half of `Rails.error` reporting posthog-rails leaves on the floor.
  #
  # posthog-rails subscribes its own `ErrorSubscriber`, but that one returns
  # early for any report made during a web request, trusting its exception
  # middleware to capture the failure instead — and the middleware only ever
  # sees an exception that escaped the controller. A `Rails.error.report`
  # from inside a request (`render_already_exists`, a waitlist mailer that
  # could not be queued, a tool run over `/mcp`) escapes nothing: it is the
  # app saying "this happened, carry on", and it would never reach PostHog.
  #
  # So this subscriber takes exactly the reports the other one skips — made
  # inside a web request — and nothing else, so no failure is reported twice.
  # Same event shape as posthog-rails produces, so one filter finds both.
  class ErrorSubscriber
    IDENTITY_KEYS = %w[user_id distinct_id].freeze

    def report(error, handled:, severity:, context:, source: nil)
      return unless PostHog::Rails.in_web_request?

      properties = {
        "$exception_source" => source || "rails_error_reporter",
        "$exception_handled" => handled,
        "$exception_severity" => severity.to_s
      }
      context.each do |key, value|
        # posthog-rails reads these two as the distinct id; here nobody is
        # identified, so they are not copied as properties either.
        next if IDENTITY_KEYS.include?(key.to_s)
        # Scalars only. The execution context also carries the controller
        # and request instances, and nothing about a request belongs on
        # the event beyond what `Telemetry::Scrub` lets through.
        next unless value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric) || [ true, false ].include?(value)

        properties["$context_#{key}"] = value.is_a?(Symbol) ? value.to_s : value
      end

      PostHog.capture_exception(error, nil, properties, mechanism: { "type" => "rails_error_reporter", "handled" => handled })
    rescue StandardError => e
      PostHog::Logging.logger.warn("in-request error report dropped: #{e.class}: #{e.message}")
    end
  end
end
