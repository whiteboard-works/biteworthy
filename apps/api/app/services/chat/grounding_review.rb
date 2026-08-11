# frozen_string_literal: true

module Chat
  # A second, cheap model checking a dietary answer against the filter's
  # own output before the user acts on it.
  #
  # This is the product's first safety property — *hidden dishes are
  # returned with their reasons, never dropped* — turned from an
  # instruction into something enforced. Until now that rule lived in the
  # server instructions, which is to say the model marking its own
  # homework: a summary that quietly omits the one dish someone is allergic
  # to reads exactly like a good answer.
  #
  # Three deliberate choices:
  #
  #   * **Fails open on infrastructure errors.** A reviewer that is down
  #     must not take the chat down with it. A missed check is worse than
  #     no check only if it is silent, so it logs — and, since 2026-08-11,
  #     logs an unreadable verdict under a *different* heading from an
  #     unreachable one. That was not a nicety: this class shipped without
  #     `output_config`, so every verdict came back as prose, failed to
  #     parse, and fell through this branch reading as a flaky upstream.
  #     "Fails open" is only defensible while somebody can tell how often
  #     it is doing so.
  #
  #   * **Anything other than a literal `true` is a flag.** Truthiness is
  #     the footgun here — `"false"`, `"no"`, and `nil` are all truthy in
  #     Ruby's eyes if you ask the wrong way, and each would wave through
  #     exactly the answer this exists to catch.
  #
  #   * **A flag gets one repair attempt, then the disclaimer.** This
  #     said a flag never retried, on the grounds that "a second full
  #     turn to repair a partly-right answer costs more than saying
  #     plainly that it may be incomplete". The arithmetic was wrong
  #     rather than the judgement: by the time the reviewer has an
  #     opinion, the transcript, the tool results and the cached prefix
  #     all exist, so the repair is *one* call against a prefix the cache
  #     already holds — not a turn. `AgentLoop#reground` makes it, hands
  #     back the objection below without storing it, and falls through to
  #     `DISCLAIMER` if the repair fails, comes back wanting tools, or is
  #     rejected a second time.
  class GroundingReview
    # Cheap and fast: this runs on top of a turn that already took a
    # minute, and it is reading, not reasoning about, the filter output.
    MODEL = "claude-haiku-4-5-20251001"

    # The tools whose output is a safety claim. Anything else the model
    # says is opinion or navigation; these are "you can eat this".
    GROUNDED_TOOLS = %w[get_menu explain_item].freeze

    DISCLAIMER = "One correction on the above: I may have left out a dish that is hidden for you, " \
                 "or described one less carefully than I should. Ask me to list the hidden dishes " \
                 "and their reasons before you order, and confirm anything serious with the restaurant."

    SCHEMA = {
      "type" => "object",
      "required" => %w[grounded],
      "additionalProperties" => false,
      "properties" => {
        "grounded" => { "type" => "boolean" },
        "problem"  => { "type" => "string" }
      }
    }.freeze

    PROMPT = <<~TEXT.freeze
      You are checking one answer against the data it was supposed to be based on.
      You are not the assistant and you are not talking to the user.

      The data is the output of a dietary filter. Every dish it marked
      `status: "hidden"` carries `reasons` saying why that specific person
      should not eat it.

      Answer `grounded: false` if the answer does ANY of these:

      1. Omits a hidden dish, or summarizes the menu in a way that leaves the
         user unaware a dish was filtered out for them.
      2. Contradicts a dish's `reasons`, or restates them wrongly.
      3. Tells the user a dish is safe for them. The filter says what did not
         match an avoid list; that is not the same as safe, and this product
         never makes that claim.

      Otherwise answer `grounded: true`. Add a one-sentence `problem` when
      you answer false.

      Judge only against the data given. The answer being brief is fine; the
      answer being wrong or quietly incomplete is not.
    TEXT

    # `usage` and `model` ride along so the caller can bill the review.
    # It is a real model call on every grounded turn and it was costing
    # money nobody was counting: the reviewer builds its own client, so
    # its `last_usage` never reached `record_usage!` and every grounded
    # turn under-reported by one haiku call.
    Result = Struct.new(:grounded, :problem, :checked, :usage, :model, keyword_init: true) do
      def flagged? = checked && grounded != true

      # **Positively verified — which is not the same as "did not
      # complain".** A reviewer that failed open answers `checked: false`,
      # and asking only `!flagged?` cannot tell that apart from a pass. So
      # anything deciding to *act* on approval has to ask this instead:
      # replacing an answer the reviewer already rejected on the strength
      # of a review that never happened is how an outage turns into a
      # silent promotion.
      def cleared? = checked && grounded == true
    end

    def initialize(client: nil)
      @injected = client
    end

    # `facts` is what the grounded tools actually returned this turn.
    def call(answer:, facts:)
      return Result.new(grounded: true, checked: false) if answer.blank? || facts.blank?

      verdict = ask(answer, facts)
      Result.new(grounded: verdict["grounded"], problem: verdict["problem"], checked: true,
                 usage: client.last_usage, model: MODEL)
    rescue StandardError => e
      # Fail open — but never silently. A reviewer that is down must not
      # take the chat with it.
      #
      # **Anything that will not fix itself is reported, not just
      # logged**, and that distinction is the whole reason this went
      # unnoticed for as long as it did. "Unavailable" is a fair name for
      # a timeout or a 503 — outside us, transient, not worth waking
      # anyone. It is the wrong name for the model answering perfectly
      # well in a shape we cannot read, which never recovers and means
      # the check is off. Filed under one heading, months of the second
      # looked exactly like a flaky upstream.
      #
      # The test is on transience rather than on a list of shape errors,
      # because the list was the first draft and it was too short: a 400
      # rejecting the derived schema arrives as `ApiError`, and a
      # `problem` string long enough to exhaust `max_tokens` arrives as
      # `TruncatedError`. Both are permanent, both mean the reviewer is
      # off, and neither is a `ValidationError`. Naming what recovers is
      # a shorter and more stable list than naming what does not.
      if transient?(e)
        Rails.logger.error("[chat] grounding review unavailable: #{e.class}: #{e.message}")
      else
        Rails.logger.error("[chat] grounding review is not working: #{e.class}: #{e.message}")
        Rails.error.report(e, handled: true, context: { component: "grounding_review" })
      end
      # A call that raised part-way may still have been billed, so the
      # usage travels on the failure path too. `@client` is whatever the
      # memoized `client` built (or the injected one), and is nil only if
      # the raise beat the first call.
      Result.new(grounded: true, checked: false, usage: @client&.last_usage, model: MODEL)
    end

    private

    # The statuses `AnthropicClient`'s own retry middleware already treats
    # as worth another attempt. Deliberately the same list: a failure the
    # client thinks is worth retrying is by definition one we expect to
    # pass on its own, which is exactly what "weather" means here.
    TRANSIENT_STATUSES = [429, 500, 502, 503, 504].freeze

    def transient?(error)
      case error
      when Faraday::TimeoutError, Faraday::ConnectionFailed then true
      when AnthropicClient::ApiError then TRANSIENT_STATUSES.include?(error.status)
      else false
      end
    end

    # Lazily built: most turns have no grounded facts and never ask, and
    # a client per turn is a connection per turn.
    def client
      @client ||= @injected || AnthropicClient.new(model: MODEL)
    end

    # **Constrained, not requested — and this reviewer has never once run
    # without it.** `response_schema` validates a reply; it does not shape
    # one. `ResponseParser` says as much in its own comment: the system
    # prompt is what has to tell the model "strict JSON, no prose". This
    # prompt does not. It says "Answer `grounded: false` if…", so haiku
    # answers in prose — probed live on 2026-08-11, the reply was:
    #
    #   grounded: false
    #
    #   problem: The answer omits that Queso was hidden… due to dairy.
    #
    # which is the correct judgement, thrown away by `JSON.parse` and
    # swallowed by the fail-open rescue below. Every grounded turn since
    # this shipped has paid for a haiku call, discarded its answer, and
    # recorded `checked: false`. The safety property this class exists to
    # enforce has been decorative, and it failed in the one direction
    # nobody would notice: open, silent, and *toward* saying the answer
    # was fine.
    #
    # `output_config` is the constrained path `Ingestion::ExtractRun`
    # already uses. The post-hoc schema stays as the check on top of it.
    def ask(answer, facts)
      client.messages_create(
        model:      MODEL,
        max_tokens: 500,
        system:     client.system_blocks({ text: PROMPT, cache: true }),
        messages:   [{ role: "user", content: [{ type: "text", text: body(answer, facts) }] }],
        output_config:   { format: { type: "json_schema",
                                     schema: ::Ingestion::SchemaForRequest.derive(SCHEMA) } },
        response_schema: SCHEMA
      )
    end

    # The filter's output is fenced the same way menu text is everywhere
    # else in this codebase: it contains dish names and descriptions that
    # came from strangers' photographs.
    def body(answer, facts)
      <<~TEXT
        <filter-output>
        #{JSON.pretty_generate(facts)}
        </filter-output>

        <answer-to-check>
        #{answer}
        </answer-to-check>
      TEXT
    end
  end
end
