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
  #     no check only if it is silent, so it logs.
  #
  #   * **Anything other than a literal `true` is a flag.** Truthiness is
  #     the footgun here — `"false"`, `"no"`, and `nil` are all truthy in
  #     Ruby's eyes if you ask the wrong way, and each would wave through
  #     exactly the answer this exists to catch.
  #
  #   * **A flag appends a disclaimer rather than retrying.** A turn is
  #     already a minute; a second full turn to repair a partly-right
  #     answer costs more than saying plainly that it may be incomplete.
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
      Rails.logger.error("[chat] grounding review unavailable: #{e.class}: #{e.message}")
      # A call that raised part-way may still have been billed, so the
      # usage travels on the failure path too. `@client` is whatever the
      # memoized `client` built (or the injected one), and is nil only if
      # the raise beat the first call.
      Result.new(grounded: true, checked: false, usage: @client&.last_usage, model: MODEL)
    end

    private

    # Lazily built: most turns have no grounded facts and never ask, and
    # a client per turn is a connection per turn.
    def client
      @client ||= @injected || AnthropicClient.new(model: MODEL)
    end

    def ask(answer, facts)
      client.messages_create(
        model:      MODEL,
        max_tokens: 500,
        system:     client.system_blocks({ text: PROMPT, cache: true }),
        messages:   [{ role: "user", content: [{ type: "text", text: body(answer, facts) }] }],
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
