# frozen_string_literal: true

module Tools
  module Meta
    # Asks the person a question with real options, and stops the turn
    # until one is chosen.
    #
    # **Why this is a tool and not a sentence.** The model could always
    # write "did you mean Nini's Taqueria or Nini's Cantina?" and wait.
    # What it gets back is a string — "the first one", "taqueria", "yes" —
    # and it has to guess which option that was. Every downstream call
    # then rests on that guess. Here the options are written down by the
    # server, the client renders exactly those, and what comes back is an
    # **option id**. There is nothing left to interpret.
    #
    # It halts the turn (`halts_turn`) because a question the model has
    # already answered around is not a question. The loop parks, the
    # person answers, and the answer arrives as this call's `tool_result`
    # — so from the model's side it reads as an ordinary tool that took a
    # while to return.
    #
    # Deliberately in `meta`, which is one of `ToolCatalog::CORE_DOMAINS`
    # and therefore resident rather than deferred. A tool the model has to
    # search for first will not be reached at the moment it is unsure —
    # that moment is exactly when it stops reaching for anything.
    class AskQuestions < Tools::Base
      audience :public

      tool_name "ask_questions"
      title "Ask the person a question and wait for their answer"
      description <<~TEXT
        Stop and ask, when going on would mean guessing at something only
        the person can settle.

        Use it when a request is genuinely ambiguous — two restaurants
        match the name, a menu edit could mean two different things, an
        avoid list could be read as a preference or an allergy — and the
        wrong branch would waste the turn or, worse, be quietly acted on.

        Do NOT use it to ask permission for a destructive call. That gate
        already exists and runs by itself; asking again is one more thing
        for the person to read. Do not use it for something a read would
        settle: search first, ask second.

        Ask about ONE thing. Two questions in a row read as an
        interrogation, and the second is usually answered by the first.
        Options must be real alternatives and must cover the likely
        answers — the person can always type instead, but an option list
        that misses the obvious choice is worse than no options.

        The turn stops here. Your next round begins with their answer.
      TEXT

      input_schema(
        required: %w[question options],
        properties: {
          question: {
            type: "string",
            description: "The question, as you would say it out loud. One sentence."
          },
          options: {
            type: "array",
            minItems: 2,
            maxItems: 5,
            description: "The real alternatives. Two to five.",
            items: {
              type: "object",
              required: %w[id label],
              additionalProperties: false,
              properties: {
                id:    { type: "string", description: "Your handle for this answer. Short, unique." },
                label: { type: "string", description: "What the person reads." },
                detail: { type: "string", description: "One clarifying line, if the label is not enough." }
              }
            }
          }
        },
        additionalProperties: false
      )

      # Read-only in the sense that matters: it stores nothing and changes
      # nothing. Saying so keeps it runnable in planning mode, where being
      # asked what you meant is if anything more useful than elsewhere.
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

      halts_turn true

      # Never actually dispatched. The loop parks on the *decision* to
      # call this, before executing — the same shape as a confirmation,
      # and for the same reason: the `tool_result` has to be the person's
      # answer, so it cannot already have been written by the tool.
      #
      # It stays defined because `Tools::Base` validates arguments against
      # the real `perform` signature as well as the schema, and because a
      # future caller reaching it directly should get something honest
      # rather than a NoMethodError.
      def self.perform(context:, question:, options:)
        ok(question: question, options: options, asked: false,
           note: "Questions are asked by the chat loop, which parks the turn. Nothing was asked here.")
      end
    end
  end
end
