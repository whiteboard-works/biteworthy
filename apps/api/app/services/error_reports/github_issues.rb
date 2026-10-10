# frozen_string_literal: true

module ErrorReports
  # The GitHub side of an error report: one issue per fingerprint, kept
  # current without ever becoming noisy.
  #
  # The first occurrence opens the issue. Later ones add a comment with
  # the count, at most once an hour; whatever arrives inside that hour
  # books one catch-up sync for when it ends. A closed issue that fires
  # again is reopened — a fix that did not take is the thing this exists
  # to catch — unless someone has labelled it `wontfix`, which mutes it:
  # still counted on the row, never touched on GitHub again.
  #
  # What leaves the database is the message's *shape* — ids, emails,
  # quoted strings, parenthesised values and numbers blanked by
  # `Capture.normalized` — never the message itself, which may quote
  # whatever a person typed.
  #
  # The target repo is configuration, never a default, and it is checked
  # to be private before anything is filed: an issue still carries a
  # backtrace and a conversation id, and `whiteboard-works/biteworthy`
  # itself is public. Until both `GITHUB_ERROR_REPORTS_TOKEN` and
  # `GITHUB_ERROR_REPORTS_REPO` are set nothing is filed, and every
  # failure still lands in `error_reports` for the day they are.
  class GithubIssues
    LABELS           = %w[bug auto-reported].freeze
    MUTE_LABEL       = "wontfix"
    COMMENT_INTERVAL = 1.hour
    # New issues per hour, across every fingerprint. A dependency flapping
    # in a way the fingerprint cannot fold must not open issues without
    # end; past this the rows still count, and the next hour opens the
    # next twenty.
    OPEN_LIMIT_PER_HOUR = 20
    API              = "https://api.github.com"

    class RequestFailed < StandardError
      attr_reader :status

      def initialize(message, status:)
        @status = status
        super(message)
      end
    end

    # A public repo as the target is a configuration mistake that would
    # publish every backtrace. Checked once per process per repo.
    class NotPrivate < StandardError; end

    def self.configured?
      ENV["GITHUB_ERROR_REPORTS_TOKEN"].present? && ENV["GITHUB_ERROR_REPORTS_REPO"].present?
    end

    def self.verified_private
      @verified_private ||= {}
    end

    def initialize(token: ENV["GITHUB_ERROR_REPORTS_TOKEN"], repo: ENV["GITHUB_ERROR_REPORTS_REPO"], conn: nil)
      @token = token
      @repo  = repo
      @conn  = conn
    end

    # The slot is given back on any failure, so one refused request
    # costs the next occurrence nothing rather than an hour of silence.
    def sync(report)
      previously = report.issue_touched_at
      unless report.claim_issue_slot!(interval: COMMENT_INTERVAL)
        schedule_catch_up(report, after: previously)
        return
      end

      ensure_private!
      report.issue_number ? update(report) : open(report)
    rescue StandardError
      report.release_issue_slot!(to: previously)
      raise
    end

    private

    # An occurrence that found the slot taken still has to reach the
    # issue — above all a recurrence right after someone closed it,
    # which may be the only one for hours.
    def schedule_catch_up(report, after:)
      due = (after || Time.current) + COMMENT_INTERVAL + 1.second
      SyncIssueJob.set(wait_until: due).perform_later(report.id) if report.schedule_sync!(at: due)
    end

    def ensure_private!
      return if self.class.verified_private[@repo]

      raise NotPrivate, "#{@repo} is not a private repository" unless request(:get, "/repos/#{@repo}")["private"] == true

      self.class.verified_private[@repo] = true
    end

    def open(report)
      # Counted, not claimed: a few workers racing past the line open a
      # few more than twenty, which is a bound that still holds.
      if ErrorReport.where(issue_opened_at: COMMENT_INTERVAL.ago..).count >= OPEN_LIMIT_PER_HOUR
        Rails.logger.warn("[error_reports] #{report.fingerprint} not filed: #{OPEN_LIMIT_PER_HOUR} issues opened this hour")
        schedule_catch_up(report, after: report.issue_touched_at)
        return
      end

      issue = request(:post, "/repos/#{@repo}/issues",
                      title: report.title, body: body_for(report), labels: LABELS)
      report.update!(issue_number: issue["number"], issue_opened_at: Time.current, issue_occurrences: report.occurrences)
    end

    def update(report)
      path  = "/repos/#{@repo}/issues/#{report.issue_number}"
      issue = request(:get, path)
      return if Array(issue["labels"]).any? { |label| label["name"] == MUTE_LABEL }

      if issue["state"] == "closed"
        request(:patch, path, state: "open")
        note = "Reopened: this came back after the issue was closed."
      else
        note = "Still happening."
      end

      since = report.occurrences - report.issue_occurrences
      request(:post, "#{path}/comments",
              body: "#{note} #{since} more since the last note (#{report.occurrences} in all), " \
                    "latest at #{report.last_seen_at.utc.iso8601}.\n\n#{context_line(report)}".strip)
      report.update!(issue_occurrences: report.occurrences)
    rescue RequestFailed => e
      # The issue is gone — deleted, or transferred out of the repo.
      # Forgetting it is what lets the next slot open a replacement
      # instead of asking after it every hour forever.
      raise unless [ 404, 410 ].include?(e.status)

      report.update!(issue_number: nil, issue_occurrences: 0)
      open(report)
    end

    def body_for(report)
      shape = Capture.normalized(report.message)
      trace = report.backtrace.presence || "(no app frames)"
      fence = fence_for(shape, trace)

      <<~MD
        Filed automatically by the API's error reporter. The same failure is counted on this issue, not filed again.

        | | |
        | --- | --- |
        | Error | `#{report.error_class}` |
        | First seen | #{report.first_seen_at.utc.iso8601} |
        | Source | #{report.source} (#{report.handled ? 'handled' : 'unhandled'}) |
        | Fingerprint | `#{report.fingerprint}` |

        #{fence}
        #{shape}
        #{fence}

        #{context_line(report)}

        <details><summary>Backtrace (app frames)</summary>

        #{fence}
        #{trace}
        #{fence}
        </details>

        Closing this issue does not mute it: it reopens on the next occurrence. Add the `#{MUTE_LABEL}` label to stop the reporter touching it.
      MD
    end

    # Longer than any run of backticks in what it fences, so a message
    # that happens to contain ``` cannot close the block early and have
    # the rest of itself rendered as live Markdown.
    def fence_for(*texts)
      longest = texts.flat_map { |text| text.scan(/`+/) }.map(&:length).max || 0
      "`" * [ longest + 1, 3 ].max
    end

    def context_line(report)
      return "" if report.context.blank?

      "Context: #{report.context.map { |key, value| "`#{key}`=`#{value.to_s.delete('`')}`" }.join(', ')}"
    end

    def request(method, path, **params)
      response = connection.public_send(method, path) do |req|
        req.body = params.to_json if params.any?
      end
      unless (200..299).cover?(response.status)
        raise RequestFailed.new("GitHub #{method.to_s.upcase} #{path} returned #{response.status}", status: response.status)
      end

      response.body
    end

    def connection
      @conn ||= Faraday.new(url: API) do |f|
        f.options.open_timeout = 5
        f.options.timeout      = 15
        f.response :json, content_type: /\bjson$/
        f.headers["authorization"]        = "Bearer #{@token}"
        f.headers["accept"]               = "application/vnd.github+json"
        f.headers["x-github-api-version"] = "2022-11-28"
        f.headers["content-type"]         = "application/json"
        f.headers["user-agent"]           = "biteworthy-api error reporter"
        f.adapter Faraday.default_adapter
      end
    end
  end
end
