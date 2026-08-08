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
      @conversation.answer_orphans!("Stopped before this ran. Nothing happened.")
      @conversation.append!(role: "assistant", content: [{ type: "text", text: message }])
      @conversation.update!(state: "active", pending_tool_call: nil)
      @aborted_state = state
      result = Result.new(state: :error, error: message)
      emit_terminal(result)
      result
    end

    def finish_run(result)
      @run.release!(
        outcome: @aborted_state ? @aborted_state : outcome_of(result),
        state:   @aborted_state || (result&.ok? ? "done" : "failed")
      )
    end

    def outcome_of(result)
      return "crashed" if result.nil?

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

      emit(type: "tool_use", name: call["name"], input: call["input"]) if confirm
      settled = confirm ? execute(call) : declined(call)
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
      MAX_ITERATIONS.times do
        response  = call_model
        blocks    = Array(response["content"])
        @conversation.append!(role: "assistant", content: blocks)

        return finish(blocks) unless response["stop_reason"] == "tool_use"

        outcome = continue_queue(blocks.select { |b| b["type"] == "tool_use" }, [])
        return outcome if outcome.awaiting_confirmation?
      end

      Result.new(state: :error, error: "Gave up after #{MAX_ITERATIONS} tool rounds without an answer.")
    end

    # Walks the turn's tool calls, stopping at the first that needs a
    # human. Returns an :awaiting_confirmation Result when it parks, or
    # nil-state :continue once every call in the turn is answered.
    def continue_queue(queue, results)
      queue.each_with_index do |call, index|
        if confirm_required?(call)
          return Result.new(state: :awaiting_confirmation, pending: park(results, queue.drop(index)))
        end

        emit(type: "tool_use", name: call["name"], input: call["input"])
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

    def confirm_required?(call)
      ToolCatalog.confirm_required?(Tools::Registry.find(call["name"]), arguments_for(call))
    end

    def execute(call)
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
      response = tool.call(server_context: server_context, **arguments_for(call))
      payload  = response.to_h
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
      text = blocks.filter_map { |b| b["text"] if b["type"] == "text" }.join("\n")
      Result.new(state: :done, text: text.presence)
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
      @run&.record_round!(@client.last_usage || {})
      response
    end

    def model_args
      {
        model:      MODEL,
        max_tokens: MAX_TOKENS,
        system:     system_prompt,
        messages:   @conversation.transcript,
        tools:      ToolCatalog.definitions(context),
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

    def system_prompt
      SystemPrompt.new(context: context, page: @page).blocks(@client)
    end

    def context
      @context ||= Tools::Context.new(server_context)
    end

    def server_context
      @server_context ||= { user_id: @conversation.user_id, public_host: @public_host }
    end

    def enforce_budget!
      if @conversation.api_cost_cents >= per_conversation_ceiling
        raise BudgetExceeded, "This conversation has reached its spend limit. Start a new one."
      end
      return if @conversation.user.is_admin?
      return if daily_spend < daily_ceiling

      raise BudgetExceeded, "Chat is over its daily budget. Try again tomorrow."
    end

    def daily_spend
      Conversation.where(created_at: Time.current.utc.beginning_of_day..).sum(:api_cost_cents)
    end

    def per_conversation_ceiling
      Integer(ENV.fetch("CHAT_CONVERSATION_CEILING_CENTS", PER_CONVERSATION_CEILING_CENTS_DEFAULT))
    end

    def daily_ceiling
      Integer(ENV.fetch("CHAT_DAILY_CEILING_CENTS", DAILY_CEILING_CENTS_DEFAULT))
    end
  end
end
