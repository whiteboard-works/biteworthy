# frozen_string_literal: true

module Chat
  # The first-party chat's tool loop.
  #
  # Same tools an MCP client gets, same audience filter, same server
  # instructions — this is the second front door onto `app/services/tools`,
  # not a second implementation of the product.
  #
  # Two properties are load-bearing:
  #
  #   * **Confirmation before a destructive call.** The loop stops at the
  #     first tool annotated `destructive_hint` and parks it. Nothing
  #     that publishes, deletes, or changes what a person is shown runs
  #     because a model decided to — a human answers first. Each such
  #     call needs its own confirmation, so a queue of them parks one at
  #     a time.
  #
  #   * **Every tool_use gets a tool_result.** The Messages API rejects a
  #     transcript where an assistant's tool_use has no answer, so a
  #     parked turn stores the results already computed alongside the
  #     calls still queued, and resuming replays them in order.
  #
  # Prompt caching: tools render into the cached prefix BEFORE system, so
  # the single `cache_control` breakpoint goes on the last system block —
  # that caches the whole tool catalog plus the instructions together.
  # Nothing per-request may sit above it, which is why the topology (also
  # stable) is concatenated into the system text rather than sent as a
  # user message.
  class AgentLoop
    MODEL          = "claude-opus-5"
    # Covers thinking AND text on Opus 5 — they share the budget.
    MAX_TOKENS     = 16_000
    # A wall against a model that loops on a failing tool. Twelve is
    # comfortably past the longest real workflow (the scan flow is seven).
    MAX_ITERATIONS = 12
    # Super admins get headroom rather than no wall at all — the turn
    # deadline still bounds the turn, and an unbounded `loop` here would
    # make a runaway cost real money before that fired.
    SUPER_ADMIN_MAX_ITERATIONS = 60

    # The other wall, because rounds are not time. One round may sit for
    # the full `ANTHROPIC_READ_TIMEOUT` (240s), and `tick!` renews the
    # lease at every step — so twelve slow rounds hold a conversation for
    # the better part of an hour while every watchdog we have reads
    # healthy. Five minutes is several times the ~60s a real turn takes.
    TURN_DEADLINE_SECONDS_DEFAULT = 300
    # Raised, not removed, for the super tier — and that raise re-admits
    # a bounded version of what the 300s wall prevents. `caller_is_super_admin?`
    # spells out why 30 minutes is an acceptable trade and no bound is not.
    SUPER_ADMIN_TURN_DEADLINE_SECONDS_DEFAULT = 1_800

    PER_CONVERSATION_CEILING_CENTS_DEFAULT = 200   # $2
    DAILY_CEILING_CENTS_DEFAULT            = 2_000 # $20/day across all non-admin chat

    Result = Struct.new(:state, :text, :pending, :error, keyword_init: true) do
      def awaiting_confirmation? = state == :awaiting_confirmation
      def ok?                    = state != :error
    end

    class BudgetExceeded < StandardError; end

    # `on_event` turns the loop into a narrator: it fires as the model
    # writes and as each tool runs, so a caller can stream progress
    # instead of showing a spinner for the length of a whole turn. When
    # it is nil the loop makes the same calls non-streaming.
    # `run:` lets the caller own the lock. CompletionJob does, because it
    # needs the run before the turn starts — the event writer stamps every
    # row with it. A direct caller passing nothing gets the lock acquired
    # and released here instead.
    def initialize(conversation, client: nil, public_host: nil, on_event: nil, run: nil, page: nil)
      @conversation = conversation
      @client       = client || AnthropicClient.new(model: MODEL)
      @public_host  = public_host
      @on_event     = on_event
      @injected_run = run
      @page         = page
    end

    # `text` starts a new turn. `confirm` answers a parked tool call:
    # true runs it, false tells the model the user said no. Passing both
    # is a caller bug — the parked call has to be settled first.
    #
    # Everything inside runs under a lock held for the whole turn. Two
    # turns racing on one conversation would interleave their messages
    # into a single ordered list, and the resulting transcript is not
    # merely confusing — it is rejected by the Messages API, which makes
    # the conversation permanently unusable rather than one turn poorer.
    def run(text: nil, confirm: nil, fingerprint: nil)
      @run = @injected_run || ConversationRun.acquire(@conversation)
      if @run.nil?
        result = Result.new(state: :error, error: "This conversation is already answering. Wait for it to finish.")
        emit_terminal(result)
        return result
      end

      # A turn that died between storing an assistant's tool calls and
      # storing their results leaves the transcript ending on an
      # unanswered `tool_use`, and an assistant message with no content at
      # all replays as a 400. Both are repaired before we add to the pile.
      @conversation.heal!
      @deadline = Time.current + turn_deadline_seconds

      result = perform(text: text, confirm: confirm, fingerprint: fingerprint)
      emit_terminal(result)
      result
    rescue ConversationRun::Aborted
      stopped("Stopped. Nothing further ran.", state: "aborted")
    rescue ConversationRun::LostLease
      # Someone else owns this conversation now. Say nothing to the user
      # about it — the run that took over is the one talking to them.
      Rails.logger.warn("[chat] run #{@run&.id} lost its lease on conversation #{@conversation.id}")
      Result.new(state: :error, error: "That turn was interrupted. Try again.")
    ensure
      finish_run(result) if @run
    end

    private

    # An abort is a first-class outcome, not an error: the transcript has
    # to stay replayable, and the user has to see what happened after a
    # reload — not just in the stream they were watching when they hit
    # stop.
    def stopped(message, state:)
      @aborted_state = state
      result = halt(message)
      emit_terminal(result)
      result
    end

    # The record half of ending a turn early: orphans answered, the reason
    # written where a reload will show it. Split out because who emits
    # differs — `stopped` is reached from a rescue and never returns
    # through `run`'s own `emit_terminal`, while a halt returned up
    # through `perform` does, and firing in both places would send the
    # client two terminal events.
    def halt(message)
      @conversation.answer_orphans!("Stopped before this ran. Nothing happened.")
      @conversation.append!(role: "assistant", content: [{ type: "text", text: message }])
      @conversation.update!(state: "active", pending_tool_call: nil)
      Result.new(state: :error, error: message)
    end

    def finish_run(result)
      @run.release!(
        outcome: @aborted_state ? @aborted_state : outcome_of(result),
        state:   @aborted_state || (result&.ok? ? "done" : "failed")
      )
    end

    def outcome_of(result)
      return "crashed" if result.nil?
      return "timed_out" if @timed_out
      return "grounding_flagged" if @grounding_flagged

      result.state.to_s
    end

    def perform(text:, confirm:, fingerprint: nil)
      if @conversation.awaiting_confirmation?
        raise ArgumentError, "answer the pending confirmation before sending a message" if text
        return resume(confirm, fingerprint)
      end

      raise ArgumentError, "text is required to start a turn" if text.blank?

      @conversation.append!(role: "user", content: [{ type: "text", text: text }])
      drive
    rescue BudgetExceeded => e
      Result.new(state: :error, error: e.message)
    rescue AnthropicClient::ApiError, AnthropicClient::Stream::IncompleteError => e
      # Upstream trouble, not a bug in us — say so plainly and leave the
      # conversation usable so the user can just try again.
      Rails.logger.error("[chat] conversation #{@conversation.id} upstream failure: #{e.class}: #{e.message}")
      Result.new(state: :error, error: "The assistant is unavailable right now. Try again in a moment.")
    end

    def resume(confirm, fingerprint = nil)
      raise ArgumentError, "confirm must be true or false" unless [true, false].include?(confirm)

      parked  = @conversation.pending_tool_call || {}
      results = Array(parked["results"])
      queue   = Array(parked["queue"])
      call    = queue.first
      return Result.new(state: :error, error: "Nothing is waiting on you.") if call.nil?

      # The answer has to be to THIS call. Without the binding, a tab left
      # open on an earlier prompt could approve whatever happens to be
      # parked now — the user would be agreeing to a sentence they never
      # read.
      #
      # Fails CLOSED: a missing stored fingerprint is a mismatch, not a
      # pass. `park` always writes one, so the only rows without it predate
      # this gate, and "absent means allowed" is how a check like this
      # quietly stops checking.
      expected = parked.dig("pending", "fingerprint")
      if expected.blank? || fingerprint != expected
        return Result.new(state: :error, error: "That confirmation is out of date. Reload and read the request again.")
      end

      emit(type: "tool_use", name: call["name"], input: call["input"], doing: doing(call)) if confirm
      # `Tools::Base` re-checks the gate, so the approval has to travel
      # with the call rather than being implied by the fact that we got
      # here. One check on both doors beats a pre-check here and a
      # different one over MCP — which is how the gate came to guard only
      # this door in the first place.
      settled = confirm ? execute(call, confirmation: grant_for(call)) : declined(call)
      emit(type: "tool_result", name: call["name"], ok: !settled[:is_error]) if confirm
      results << settled
      @conversation.update!(state: "active", pending_tool_call: nil)

      # The rest of the queue still runs through the gate — confirming
      # one destructive call does not pre-authorize the next.
      outcome = continue_queue(queue.drop(1), results)
      return outcome if outcome.awaiting_confirmation?

      drive
    end

    def drive
      rounds = max_iterations
      rounds.times do
        return over_deadline if past_deadline?

        response  = call_model
        blocks    = Array(response["content"])
        @conversation.append!(role: "assistant", content: blocks)

        return finish(blocks) unless response["stop_reason"] == "tool_use"

        outcome = continue_queue(blocks.select { |b| b["type"] == "tool_use" }, [])
        return outcome if outcome.awaiting_confirmation?
      end

      Result.new(state: :error, error: "Gave up after #{rounds} tool rounds without an answer.")
    end

    # Checked between rounds, which is the only place the transcript is
    # whole: every `tool_use` from the previous round already has its
    # `tool_result`. The turn therefore overruns by at most one round, and
    # ends the way a stop does — written down, orphans answered, still
    # replayable — rather than as a raise nobody stored.
    def past_deadline? = Time.current >= @deadline

    def over_deadline
      Rails.logger.warn("[chat] conversation #{@conversation.id} passed its #{turn_deadline_seconds}s turn deadline")
      # Recorded as the run's outcome, not its state, the same way a
      # grounding flag is: `state` is a small enum with a CHECK constraint
      # behind it, and "failed" is true — `outcome` is where why lives.
      @timed_out = true
      halt("That took too long, so I stopped it. Nothing further ran — ask again to pick it up.")
    end

    # Walks the turn's tool calls, stopping at the first that needs a
    # human. Returns an :awaiting_confirmation Result when it parks, or
    # nil-state :continue once every call in the turn is answered.
    def continue_queue(queue, results)
      queue.each_with_index do |call, index|
        if confirm_required?(call)
          return Result.new(state: :awaiting_confirmation, pending: park(results, queue.drop(index)))
        end

        emit(type: "tool_use", name: call["name"], input: call["input"], doing: doing(call))
        result = execute(call)
        emit(type: "tool_result", name: call["name"], ok: !result[:is_error])
        results << result
      end

      @conversation.append!(role: "user", content: results) if results.any?
      Result.new(state: :continue)
    end

    # Parks the head of the queue and returns what a client needs to draw
    # the prompt: the declared sentence, and a fingerprint the answer must
    # carry back.
    #
    # The fingerprint is computed **once, here** and stored — never
    # recomputed from the parked row. jsonb does not preserve key order, so
    # a hash derived from the round-tripped input would not reliably match
    # one derived from the live call.
    def park(results, queue)
      call        = queue.first
      tool        = Tools::Registry.find(call["name"])
      fingerprint = Digest::SHA256.hexdigest(JSON.generate([call["name"], call["input"]]))
      pending     = {
        "name"        => call["name"],
        "input"       => call["input"],
        "prompt"      => tool&.confirmation_prompt_for(arguments_for(call)),
        "fingerprint" => fingerprint
      }

      @conversation.update!(
        state: "awaiting_confirmation",
        pending_tool_call: { "results" => results, "queue" => queue, "pending" => pending }
      )
      pending
    end

    # The sentence a person reads while the call runs.
    def doing(call)
      Tools::Registry.find(call["name"])&.running_description_for(arguments_for(call))
    end

    def confirm_required?(call)
      # A caller with `skip_confirmations` never parks. Checked here as
      # well as in `Tools::Base#confirmation_gate` because the chat door
      # parks *before* the tool boundary is reached — without this the
      # turn would stop and wait for an answer that the gate below would
      # then have waved through anyway.
      return false if context.skip_confirmations?

      ToolCatalog.confirm_required?(Tools::Registry.find(call["name"]), arguments_for(call))
    end

    # The person answered the question `park` wrote and the fingerprint
    # proved it was this call. Minting is that answer in a form
    # `Tools::Base` can verify; a model never mints one.
    def grant_for(call)
      Tools::Confirmation.mint(
        tool: call["name"], args: arguments_for(call), user_id: @conversation.user_id
      )
    end

    def execute(call, confirmation: nil)
      tick!
      tool = Tools::Registry.find(call["name"])
      if tool.nil?
        return tool_result(call, { error: "unknown_tool", message: "No tool named #{call['name']}." }, error: true)
      end

      # No rescue here on purpose. `Tools::Base.call` is the boundary: it
      # validates the model's arguments, authorizes, and converts every
      # failure — domain error or tool bug — into an `isError` response.
      # A second rescue at this call site is how the two front doors drift
      # apart on what a broken tool looks like.
      # `.except(:confirmation)` is load-bearing: duplicate keywords are
      # last-wins in Ruby, so a model that put a `confirmation` key in its
      # own tool input would otherwise overwrite the grant minted after a
      # person tapped approve — untrusted input outranking the server's
      # own answer, and an approved removal silently not happening.
      response = tool.call(
        server_context: server_context,
        **arguments_for(call).except(:confirmation),
        confirmation: confirmation
      )
      payload  = response.to_h
      remember_facts(call, payload)
      tool_result(call, payload[:structuredContent] || payload[:content], error: payload[:isError] == true)
    end

    def declined(call)
      tool_result(
        call,
        { error: "declined",
          message: "The user declined to run #{call['name']}. Do not call it again unless they ask." },
        error: true
      )
    end

    def tool_result(call, content, error: false)
      {
        type:        "tool_result",
        tool_use_id: call["id"],
        content:     [{ type: "text", text: content.is_a?(String) ? content : JSON.pretty_generate(content) }],
        is_error:    error
      }
    end

    # Tool schemas are symbol-keyed keyword args; the API hands back
    # string keys.
    def arguments_for(call)
      (call["input"] || {}).to_h.symbolize_keys
    end

    def finish(blocks)
      text = blocks.filter_map { |b| b["text"] if b["type"] == "text" }.join("\n").presence
      Result.new(state: :done, text: ground(text))
    end

    # The filter's own output for this turn, kept so a second model can
    # check the answer against it. Only the tools that make a safety claim
    # count — everything else the model says is navigation or opinion.
    def remember_facts(call, payload)
      return unless GroundingReview::GROUNDED_TOOLS.include?(call["name"])
      return if payload[:isError] == true

      (@facts ||= []) << payload[:structuredContent]
    end

    # Safety Property 1, enforced rather than instructed: a summary that
    # quietly drops the one dish someone is allergic to reads exactly like
    # a good answer, so something other than the author has to look.
    def ground(text)
      # Nothing to check against means nothing to check. Most turns are
      # navigation or opinion, and a review of those is a model call spent
      # on nothing.
      return text if @facts.blank? || text.blank?

      verdict = GroundingReview.new.call(answer: text, facts: @facts)
      # Billed whether or not it flagged anything: the call happened. It
      # is a haiku call priced at haiku rates, not the loop's model.
      record_review_usage(verdict)
      return text unless verdict.flagged?

      Rails.logger.warn("[chat] grounding flagged conversation #{@conversation.id}: #{verdict.problem}")
      # Recorded as the run's outcome rather than written here, because
      # `release!` in the ensure block owns that column and would overwrite
      # a direct write with "done".
      @grounding_flagged = true
      @conversation.append!(role: "assistant",
                            content: [{ type: "text", text: GroundingReview::DISCLAIMER }])
      emit(type: "text_delta", text: "\n\n#{GroundingReview::DISCLAIMER}")
      [text, GroundingReview::DISCLAIMER].compact.join("\n\n")
    end

    # The reviewer's spend lands on the conversation but deliberately not
    # on `rounds`: a round is a turn of the agent loop, and inflating that
    # count would make "6 rounds" stop meaning what the metric was added
    # to mean. The tokens and the cost still accrue to the run.
    def record_review_usage(verdict)
      return if verdict.usage.blank?

      @conversation.record_usage!(verdict.usage, model: verdict.model)
      @run&.record_side_call!(verdict.usage, model: verdict.model)
    end

    def call_model
      tick!
      enforce_budget!

      response =
        if @on_event
          @client.messages_stream(**model_args) { |kind, text| emit(type: "#{kind}_delta", text: text) }
        else
          @client.messages_create(**model_args)
        end
      @conversation.record_usage!(@client.last_usage, model: MODEL)
      @run&.record_round!(@client.last_usage || {}, model: MODEL)
      response
    end

    # Only `messages` grows within a turn. Everything else here is the
    # material that sits at or above the prompt-cache breakpoint, and
    # rebuilding it for each of up to twelve rounds bought nothing: the
    # catalogue re-rendered 44 JSON schemas, the topology walked the
    # registry twice more, and the profile snapshot went back to Postgres
    # — all to produce the bytes the cache is keyed on.
    def model_args
      {
        model:      MODEL,
        max_tokens: MAX_TOKENS,
        system:     system_prompt,
        messages:   @conversation.transcript,
        tools:      tool_definitions,
        thinking:   { type: "adaptive" }
      }
    end

    def emit(payload)
      @on_event&.call(payload)
    end

    # Refreshes the lease and reads the stop flag in one statement. Called
    # at every lifecycle event rather than once per turn: a turn is a
    # minute of model calls and tool runs, and a stop button that is only
    # honoured at the end is not a stop button.
    def tick!
      @run&.tick!
    end

    # The one place a turn's outcome becomes an event, so a streaming
    # caller can close on it without inspecting the Result itself.
    def emit_terminal(result)
      case result.state
      when :done                  then emit(type: "done", text: result.text)
      when :awaiting_confirmation then emit(type: "awaiting_confirmation", tool: result.pending)
      when :error                 then emit(type: "error", message: result.error)
      end
    end

    # Built once per turn. The profile snapshot it carries is a snapshot
    # by design — the prompt itself tells the model to trust a tool's
    # response over it if the profile changes mid-turn — and the timestamp
    # riding alongside it is what "now" was when the user asked.
    def system_prompt
      @system_prompt ||= SystemPrompt.new(context: context, page: @page).blocks(@client)
    end

    def tool_definitions
      @tool_definitions ||= ToolCatalog.definitions(context)
    end

    def context
      @context ||= Tools::Context.new(server_context)
    end

    def server_context
      @server_context ||= { user_id: @conversation.user_id, public_host: @public_host }
    end

    # Both ceilings are pre-call: the check runs before the request that
    # would cross them, so a turn overshoots by at most one round's cost.
    # That is why a $2 conversation reports 203¢ — post-call accounting
    # could report the exact figure but could no longer refuse anything.
    def enforce_budget!
      return if caller_is_super_admin?

      # The message reads the same column the guard compares. Not fixing a
      # live bug — `append!` takes `with_lock` before every `call_model`
      # and that reloads the row, so `api_cost_cents` is fresh in practice
      # — but `increment!` refreshes only the column it touched and
      # `api_cost_cents` is generated, so the old form was correct only by
      # way of an incidental reload somewhere else.
      if @conversation.api_cost_micro_cents >= micro(per_conversation_ceiling)
        raise BudgetExceeded,
              "This conversation has spent #{ceil_cents(@conversation.api_cost_micro_cents)}¢ " \
              "of its #{per_conversation_ceiling}¢ limit. Start a new one."
      end
      return if caller_is_admin?
      return if daily_spend_micro < micro(daily_ceiling)

      raise BudgetExceeded,
            "Chat has spent #{ceil_cents(daily_spend_micro)}¢ of its " \
            "#{daily_ceiling}¢ daily budget. Try again tomorrow."
    end

    def micro(cents)       = cents * 1_000_000
    def ceil_cents(micros) = (micros / 1_000_000.0).ceil

    # `with_lock` on the conversation clears its association cache, so
    # every append made the next round re-load the same user row.
    def caller_is_admin?
      return @caller_is_admin if defined?(@caller_is_admin)

      @caller_is_admin = @conversation.user.is_admin?
    end

    # The super tier clears both spend ceilings and the round cap.
    #
    # The wall-clock deadline is **raised, not cleared** — 300s to 1,800s
    # — and the honest reading of that is that it re-admits a smaller
    # version of the problem the 300s wall was added for: a wedged turn
    # keeps `tick!` renewing its 120s lease, so the run looks healthy to
    # every watchdog for as long as the deadline allows. Two things make
    # 30 minutes an acceptable trade where "no deadline at all" would not
    # be. The lock is **per conversation** (a partial unique index on
    # `conversation_id`), so the blast radius is the one conversation the
    # operator is sitting in front of, not the chat. And that operator
    # has `DELETE /conversations/:id/run` — a wedge here is recoverable
    # by the person who caused it, which is not true of a community
    # caller's turn. Removing the bound entirely would leave nothing but
    # that button, and a closed laptop does not press it.
    def caller_is_super_admin?
      return @caller_is_super_admin if defined?(@caller_is_super_admin)

      @caller_is_super_admin = @conversation.user.is_super_admin?
    end

    def max_iterations
      caller_is_super_admin? ? SUPER_ADMIN_MAX_ITERATIONS : MAX_ITERATIONS
    end

    # An aggregate over every conversation opened today, read once per
    # turn instead of once per round. What this turn itself has spent
    # since then is added back, so the round that crosses the ceiling
    # still trips it — a runaway loop is the case the ceiling exists for,
    # and it is the only spender a memoized baseline could miss by much.
    def daily_spend_micro
      unless defined?(@daily_spend_baseline)
        @daily_spend_baseline = Conversation.where(created_at: Time.current.utc.beginning_of_day..)
                                            .sum(:api_cost_micro_cents)
        @own_spend_baseline   = @conversation.api_cost_micro_cents
      end

      @daily_spend_baseline + (@conversation.api_cost_micro_cents - @own_spend_baseline)
    end

    def per_conversation_ceiling
      Integer(ENV.fetch("CHAT_CONVERSATION_CEILING_CENTS", PER_CONVERSATION_CEILING_CENTS_DEFAULT))
    end

    def daily_ceiling
      Integer(ENV.fetch("CHAT_DAILY_CEILING_CENTS", DAILY_CEILING_CENTS_DEFAULT))
    end

    def turn_deadline_seconds
      return super_admin_turn_deadline_seconds if caller_is_super_admin?

      Integer(ENV.fetch("CHAT_TURN_DEADLINE_SECONDS", TURN_DEADLINE_SECONDS_DEFAULT))
    end

    def super_admin_turn_deadline_seconds
      Integer(ENV.fetch("CHAT_SUPER_ADMIN_TURN_DEADLINE_SECONDS",
                        SUPER_ADMIN_TURN_DEADLINE_SECONDS_DEFAULT))
    end
  end
end
