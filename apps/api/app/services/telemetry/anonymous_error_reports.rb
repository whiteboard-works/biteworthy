# frozen_string_literal: true

module Telemetry
  # posthog-rails' ErrorSubscriber always lifts `user_id` / `distinct_id` from
  # the report context into `capture_exception`'s distinct id — even when
  # `capture_user_context` is off. That would attach a person to a server
  # error, which ADR 0009 forbids. Strip those keys before the gem sees the
  # report so in-request capture still happens, anonymously.
  module AnonymousErrorReports
    IDENTITY_KEYS = %w[user_id distinct_id].freeze

    def report(error, handled:, severity:, context:, source: nil)
      super(
        error,
        handled: handled,
        severity: severity,
        context: context.reject { |key, _| IDENTITY_KEYS.include?(key.to_s) },
        source: source
      )
    end
  end
end
