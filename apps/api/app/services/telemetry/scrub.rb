# frozen_string_literal: true

module Telemetry
  # What leaves the box for PostHog, minus what must not: the request
  # body, the caller's address, and anything shaped like an email or a
  # credential.
  #
  # Two hooks call this (config/initializers/posthog.rb). `before_send` on
  # the events client sees every event the Ruby SDK is about to queue — in
  # practice the `$exception` events posthog-rails captures — and
  # `logs_before_send` sees every `Rails.logger` line about to be forwarded
  # to PostHog Logs. Both run on the hot path, so this is a handful of
  # regexps and nothing that allocates much.
  module Scrub
    # Properties posthog-rails attaches to an exception that must not reach
    # a third party's store. `$request_params` is the request body after
    # the parameter filter, which cannot see inside a chat message or a
    # review — either can name a diet. `$ip` is the caller's address.
    # `$referrer` is a full URL with its query, and `?profile=celiac` is a
    # query the web client goes out of its way to strip from page views.
    DROPPED_EVENT_PROPERTIES = %w[$request_params $ip $referrer].freeze

    # kamal-proxy polls /up every five seconds. `silence_healthcheck_path`
    # silences the STDOUT logger for those requests, but silence is a
    # LoggerSilence feature and the forwarder is a plain Logger that does
    # not have it, so its copy of every line still arrives here. The
    # "Started" line is logged before the request context exists, so it is
    # matched by its text; the lines inside the request carry the path.
    HEALTHCHECK_PATH = "/up"
    HEALTHCHECK_LINE = /\AStarted \w+ "#{HEALTHCHECK_PATH}"/

    # Rails logs every request's parameters at info, and `filter_parameters`
    # blanks only the keys it names. A chat message, a review, a bio, an
    # avoid list — each is a free-text or health field under a key nobody
    # would think to list. The line is useless without the request anyway,
    # so it does not leave the box at all.
    PARAMETERS_LINE = /\A\s*Parameters: /

    # Lines that quote text a model wrote about a person's answer. The
    # grounding reviewer's verdict names what it found wrong — "the answer
    # says this dish is safe for a peanut allergy" — which is the diet in
    # other words. The line stays (it is how a flagged turn is found); the
    # text stays on the box.
    MODEL_TEXT_LINE = /\A(\[chat\] grounding flagged conversation \S+:).*/m

    # Every value in a query string. A claim's verify link (`?t=`), a
    # password reset, a share link's encoded avoid list (`?p=`), the diet a
    # menu is filtered by (`?profile=`) — a list of key names is a list
    # someone forgets to extend, and Rails' own parameter filter blanks the
    # request line's query only for the keys it names. Keys stay, values go.
    QUERY_VALUE = /([?&][^=&\s"']+=)[^&\s"']*/

    # Active Job logs every job's arguments on enqueue and on perform. For
    # Devise's mail job that is the raw reset token as a bare string, which
    # no credential pattern can recognize; for others it is whatever the
    # caller passed. The job class and id stay; the arguments stay on the box.
    JOB_ARGUMENTS = / with arguments: .*/m

    # The API's one route with a person in the path (`GET /users/:handle`).
    # Masked the way the web client masks `/u/<handle>`; the query is
    # handled upstream by `filter_parameters` (Rails logs `filtered_path`).
    USER_PATH = %r{(/api/v1/users/)[A-Za-z0-9_]+}

    # Rails' request line is the one place the client address is printed:
    # `Started GET "/x" for 203.0.113.9 at 2026-10-10 ...`. Matched on the
    # line's shape so an IPv6 address goes too, without a regexp loose
    # enough to eat timestamps.
    REQUEST_LINE_IP = /(\bfor )(\S+)( at \d{4}-\d{2}-\d{2})/
    IPV4            = /\b(?:\d{1,3}\.){3}\d{1,3}\b/
    EMAIL           = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/

    # Every key prefix the app holds (Anthropic, GitHub, TypeSafe, PostHog),
    # a bearer token, a JWT, a Resend key, and the password in a connection
    # URL. A credential in a log line is a bug, and the fix is upstream;
    # this just keeps it from being copied somewhere else first.
    KEY_WITH_PREFIX = /\b(sk-ant-|ghp_|github_pat_|apikey_|phx_|phs_|Bearer )\S+/
    RESEND_KEY      = /\bre_[A-Za-z0-9_]{20,}/
    JWT             = /\beyJ[\w-]{10,}\.[\w-]+\.[\w-]+/
    URL_PASSWORD    = %r{://[^/\s:@]+:[^@\s]+@}

    module_function

    # `before_send`: the event hash the SDK is about to queue. Strips the
    # request and the caller from it, runs every string it still carries
    # — the exception messages above all: a unique-index violation quotes
    # the email, an upstream error can echo what a person typed — through
    # the text scrubber, and tags the process role. Returns the event,
    # never nil, so nothing is dropped here.
    def event(event)
      properties = event[:properties]
      return event unless properties.is_a?(Hash)

      DROPPED_EVENT_PROPERTIES.each do |key|
        properties.delete(key)
        properties.delete(key.to_sym)
      end
      properties.each { |key, value| properties[key] = deep(value) unless key.to_s == "$exception_list" }
      Array(properties["$exception_list"]).each do |exception|
        next unless exception.is_a?(Hash) && exception["value"].is_a?(String)

        exception["value"] = text(exception["value"])
      end
      properties["service.role"] = role if role
      event
    end

    # Every string in a property, however nested: posthog-rails serializes a
    # report's context as it was given, hashes and arrays included.
    def deep(value)
      case value
      when String then text(value)
      when Hash   then value.transform_values { |v| deep(v) }
      when Array  then value.map { |v| deep(v) }
      else value
      end
    end

    # `logs_before_send`: one log record (:timestamp, :severity, :body,
    # :attributes) about to be forwarded, or nil to drop it. Health-check
    # lines are dropped; the rest — request lines, job lines, whatever the
    # app logged — is scrubbed and tagged.
    def log(record)
      body = record[:body].to_s
      attributes = (record[:attributes] ||= {})
      return nil if attributes["url.path"] == HEALTHCHECK_PATH || HEALTHCHECK_LINE.match?(body)
      return nil if PARAMETERS_LINE.match?(body)

      record[:body] = text(body.sub(MODEL_TEXT_LINE, '\1 <model text>').sub(JOB_ARGUMENTS, " with arguments: <redacted>"))
      attributes["url.path"] = text(attributes["url.path"]) if attributes["url.path"].is_a?(String)
      attributes["url.full"] = text(attributes["url.full"]) if attributes["url.full"].is_a?(String)
      attributes["service.role"] = role if role
      record
    end

    def text(string)
      string
        .gsub(URL_PASSWORD, "://<redacted>@")
        .gsub(KEY_WITH_PREFIX) { "#{Regexp.last_match(1)}<redacted>" }
        .gsub(RESEND_KEY, "re_<redacted>")
        .gsub(JWT, "<jwt>")
        .gsub(QUERY_VALUE, '\1<q>')
        .gsub(REQUEST_LINE_IP, '\1<ip>\3')
        .gsub(IPV4, "<ip>")
        .gsub(EMAIL, "<email>")
        .gsub(USER_PATH, '\1:handle')
    end

    # `web` or `worker` — the two Kamal roles (config/deploy.yml). Both run
    # the same image, and a log line or an error means something different
    # on each.
    def role
      ENV["APP_ROLE"].presence
    end
  end
end
