# frozen_string_literal: true

require "digest"

module ErrorReports
  # Turns an exception the app reported into the small, plain record the
  # job files — and decides which failures count as the same one.
  #
  # Everything here survives the trip through Active Job: strings,
  # numbers, booleans, and a flat Hash of the same. Nothing that needs
  # the exception, the request, or the job to still exist.
  module Capture
    MESSAGE_CHARS = 1_000
    TITLE_CHARS   = 110
    FRAMES        = 15

    # Things the fingerprint must not depend on, and the record must not
    # keep: record ids, memory addresses, email addresses, long numbers,
    # measurements, decimals, quoted strings, and anything in parentheses
    # — which is where Postgres puts the values it echoes, quoted
    # (`Key (email)=(a@b.com)`) and unquoted alike (`Failing row contains
    # (Jane, pregnant, hunter2)`). Two failures that differ only there
    # are the same bug — and that is also where a person's text ends up
    # when a parser or a constraint quotes it. Only the `normalized`
    # shape is stored: an `error_reports` row belongs to no account, so
    # deleting an account could never reach a message that quoted them.
    UUID     = /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/
    HEX      = /\b0x\h+\b/
    EMAIL    = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/
    QUOTED   = /"[^"]*"|'[^']*'/
    PARENS   = /\([^()]*\)/
    DECIMAL  = /\d+\.\d+/
    MEASURE  = /\d+(?:ms|s|m|h|kb|mb|gb|b)\b/i
    LONG_N   = /\d{4,}/

    # Credentials have no business in an issue, and the parameter filter
    # cannot see inside a message string: every key prefix the app holds
    # (Anthropic, GitHub, TypeSafe, Resend, AWS-style), a JWT, a bearer
    # token, and the password in a connection URL.
    SECRET = Regexp.union(
      /(sk-ant-|ghp_|github_pat_|apikey_|re_|Bearer )[^\s,;)]+/,
      /AKIA[0-9A-Z]{16}/,
      /eyJ[\w-]{10,}\.[\w-]+\.[\w-]+/,
      %r{://[^/\s:@]+:[^@\s]+@}
    )

    SCALARS = [ String, Symbol, Numeric, TrueClass, FalseClass, NilClass ].freeze

    def self.call(error, context: {}, source: "application", handled: true)
      shape  = normalized(scrubbed(error.message.to_s))
      frames = app_frames(error)
      plain  = plain_context(context)

      {
        "fingerprint" => fingerprint(error, shape, frames.first),
        "error_class" => error.class.name,
        "title"       => title(error, shape, plain),
        "message"     => shape.truncate(MESSAGE_CHARS),
        "source"      => source.to_s,
        "handled"     => handled ? true : false,
        "context"     => plain,
        "backtrace"   => frames.join("\n").presence
      }
    end

    # Same class, same message shape, same place in our code.
    #
    # The frame loses its line number on purpose: a deploy that shifts a
    # file down by one line would otherwise open a fresh issue for a bug
    # that already has one.
    def self.fingerprint(error, shape, frame)
      key = [ error.class.name, shape, frame.to_s.sub(/:\d+:/, ":") ].join("|")
      Digest::SHA256.hexdigest(key).first(16)
    end

    # The shape of a message with the variable parts blanked. Short
    # numbers survive on purpose: a 529 and a 401 are different problems.
    # Parentheses go until none nest, so `((a, b), c)` is one blank.
    def self.normalized(message)
      shape = message.gsub(UUID, "<id>").gsub(HEX, "<addr>").gsub(EMAIL, "<email>").gsub(QUOTED, "<str>")
      loop do
        collapsed = shape.gsub(PARENS, "⟨…⟩")
        break if collapsed == shape

        shape = collapsed
      end
      shape.gsub("⟨…⟩", "(…)").gsub(DECIMAL, "<n>").gsub(MEASURE, "<n>").gsub(LONG_N, "<n>")
    end

    # "[chat] AnthropicClient::ApiError: Anthropic API returned 529 …" —
    # where it happened, what it was, and the first line of why.
    def self.title(error, shape, plain)
      where = plain["component"].presence || plain["job"].presence || plain["controller"].presence
      lead  = shape.lines.first.to_s.strip.presence || error.class.name
      [ where && "[#{where}]", "#{error.class.name}: #{lead}" ].compact.join(" ").truncate(TITLE_CHARS)
    end

    def self.app_frames(error)
      Rails.backtrace_cleaner.clean(Array(error.backtrace)).first(FRAMES)
    end

    # Only what can be serialized and shown: the job's and controller's
    # names rather than their instances (Active Job and Action Dispatch
    # put the instances in the execution context), scalar values, and
    # nothing the parameter filter would hide from the logs.
    def self.plain_context(context)
      plain = {}
      context.to_h.each do |key, value|
        case key.to_sym
        when :job        then plain["job"] = name_of(value)
        when :controller then plain["controller"] = [ name_of(value), value.try(:action_name) ].compact.join("#")
        else
          next unless SCALARS.any? { |kind| value.is_a?(kind) }

          plain[key.to_s] = value.is_a?(Symbol) ? value.to_s : value
        end
      end
      filter.filter(plain)
    end

    def self.name_of(value)
      value.is_a?(String) ? value : value.class.name
    end

    # Built once: this runs on the failing path, and compiling twenty
    # patterns per report is the kind of cost that only shows up during
    # the storm it is meant to survive.
    def self.filter
      @filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end

    def self.scrubbed(message)
      message.gsub(SECRET) { |match| match.start_with?("://") ? "://<redacted>@" : "#{Regexp.last_match(1)}<redacted>" }
    end
  end
end
