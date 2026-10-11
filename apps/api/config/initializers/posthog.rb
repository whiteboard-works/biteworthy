# frozen_string_literal: true

# PostHog is where the API's errors and logs go (ADR 0009): project 652080,
# the one the web and mobile clients send their funnel events to.
#
# Everything here is keyed off POSTHOG_API_KEY. Unset — development, CI, a
# self-hosted clone — the client is disabled, and every capture, every
# forwarded log line, and the error subscriber are no-ops, so nothing below
# needs an environment check. The key is the project's public client
# token (deploy.yml `env.clear`), not a secret.
#
# What flows out:
#
#   * Exceptions. Every `Rails.error.report` call (the chat loop, the tools,
#     the controllers) and the unhandled ones Rails reports itself — a 500,
#     a job whose retries ran out — become `$exception` events. Errors
#     that are rescued and rendered (a 404, a 422) are not reported.
#     posthog-rails covers the unhandled ones and the reports made outside
#     a request; `Telemetry::ErrorSubscriber` covers the reports made
#     inside one, which posthog-rails skips.
#   * Logs. `Rails.logger` is broadcast to PostHog Logs over OTLP, info and
#     up, through `Telemetry::Scrub.log`, which also drops the health
#     checks `silence_healthcheck_path` keeps out of STDOUT.
#   * Nothing about who. No user id is attached to a server error
#     (`capture_user_context` off), the request body and the caller's IP
#     are stripped and every message is scrubbed (`Telemetry::Scrub.event`),
#     and the distinct id the SDK fills in is random — the stance `/privacy`
#     takes for client events.
PostHog::Rails.configure do |config|
  config.auto_capture_exceptions = true
  config.report_rescued_exceptions = false
  # `ApplicationJob` reports a job that exhausted its retries to
  # `Rails.error` itself (Solid Queue swallows the exception inside the app
  # executor and files a failed execution, so the executor never sees it),
  # and the subscriber gets it from there. Instrumenting ActiveJob as well
  # would report every attempt of a job that `retry_on` was about to retry.
  config.auto_instrument_active_job = false
  config.capture_user_context = false
  # No client sends X-PostHog-* headers; refusing them means a header
  # cannot assign an identity to a server event either.
  config.use_tracing_headers = false

  config.logs_enabled = true
  config.logs_level = :info
  config.logs_before_send = ->(record) { Telemetry::Scrub.log(record) }
end

# The SDK logs "api_key is missing" at error level on every boot without a
# key, which is every development boot and every CI run.
PostHog.init(silence_disabled_client_error: true) do |config|
  config.api_key = ENV["POSTHOG_API_KEY"]
  config.host = ENV.fetch("POSTHOG_HOST", "https://us.i.posthog.com")
  config.before_send = ->(event) { Telemetry::Scrub.event(event) }
  # Through the SDK's own logger: its prefix is what keeps the log
  # forwarder from shipping PostHog's complaints about PostHog back to it.
  config.on_error = ->(status, message) { PostHog::Logging.logger.warn("#{status}: #{message}") }
  config.test_mode = Rails.env.test?
end

# PostHog acknowledges an OTLP/protobuf log export with `200` and a JSON
# `{}` body, where OTLP has the response use the request's encoding. The
# Ruby exporter protobuf-decodes that body anyway, fails, and prints an
# ERROR line to STDOUT for every batch it just delivered, one or more a
# second whenever the app is logging. That one complaint is dropped here;
# everything else OpenTelemetry has to say still reaches the default
# handler. Reported to PostHog 2026-10-11; remove once the endpoint
# answers in kind.
require "opentelemetry-api"

otel_default_error_handler = OpenTelemetry.error_handler
OpenTelemetry.error_handler = lambda do |exception: nil, message: nil|
  next if message&.start_with?("unexpected error decoding ExportLogsServiceResponse")

  otel_default_error_handler.call(exception: exception, message: message)
end

Rails.application.config.after_initialize do
  Rails.error.subscribe(Telemetry::ErrorSubscriber.new)
end
