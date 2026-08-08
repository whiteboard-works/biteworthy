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
    def initialize(conversation, client: nil, public_host: nil, on_event: nil)
      @conversation = conversation
      @client       = client || AnthropicClient.new(model: MODEL)
      @public_host  = public_host
      @on_event     = on_event
    end

    # `text` starts a new turn. `confirm` answers a parked tool call:
    # true runs it, false tells the model the user said no. Passing both
    # is a caller bug — the parked call has to be settled first.
    def run(text: nil, confirm: nil)
      result = perform(text: text, confirm: confirm)
      emit_terminal(result)
      result
    end

    private

    def perform(text:, confirm:)
      if @conversation.awaiting_confirmation?
        raise ArgumentError, "answer the pending confirmation before sending a message" if text
        return resume(confirm)
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

    def resume(confirm)
      raise ArgumentError, "confirm must be true or false" unless [true, false].include?(confirm)

      parked  = @conversation.pending_tool_call || {}
      results = Array(parked["results"])
      queue   = Array(parked["queue"])
      call    = queue.first
      return Result.new(state: :error, error: "Nothing is waiting on you.") if call.nil?

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
          park(results, queue.drop(index))
          return Result.new(
            state: :awaiting_confirmation,
            pending: { "name" => call["name"], "input" => call["input"] }
          )
        end

        emit(type: "tool_use", name: call["name"], input: call["input"])
        result = execute(call)
        emit(type: "tool_result", name: call["name"], ok: !result[:is_error])
        results << result
      end

      @conversation.append!(role: "user", content: results) if results.any?
      Result.new(state: :continue)
    end

    def park(results, queue)
      @conversation.update!(
        state: "awaiting_confirmation",
        pending_tool_call: { "results" => results, "queue" => queue }
      )
    end

    def confirm_required?(call)
      ToolCatalog.confirm_required?(Tools::Registry.find(call["name"]))
    end

    def execute(call)
      tool = Tools::Registry.find(call["name"])
      if tool.nil?
        return tool_result(call, { error: "unknown_tool", message: "No tool named #{call['name']}." }, error: true)
      end

      response = tool.call(server_context: server_context, **arguments_for(call))
      payload  = response.to_h
      tool_result(call, payload[:structuredContent] || payload[:content], error: payload[:isError] == true)
    rescue StandardError => e
      # A bug in a tool must not kill the conversation, but it must not
      # look like a recoverable domain error either — the model is told
      # plainly that this one is broken so it stops retrying it.
      Rails.logger.error("[chat] tool #{call['name']} raised: #{e.class}: #{e.message}")
      tool_result(call, { error: "tool_failed", message: "#{call['name']} failed and cannot be retried." }, error: true)
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
      enforce_budget!

      response =
        if @on_event
          @client.messages_stream(**model_args) { |kind, text| emit(type: "#{kind}_delta", text: text) }
        else
          @client.messages_create(**model_args)
        end
      @conversation.record_usage!(@client.last_usage, model: MODEL)
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

    # The one place a turn's outcome becomes an event, so a streaming
    # caller can close on it without inspecting the Result itself.
    def emit_terminal(result)
      case result.state
      when :done                  then emit(type: "done", text: result.text)
      when :awaiting_confirmation then emit(type: "awaiting_confirmation", tool: result.pending)
      when :error                 then emit(type: "error", message: result.error)
      end
    end

    # One cache breakpoint, on the last system block, so the cached
    # prefix is [tools][instructions][topology]. All three are stable
    # for a given caller, which is what makes the second turn cheap.
    def system_prompt
      @client.system_blocks(
        { text: Tools::Instructions.text },
        { text: Tools::Topology.markdown(context), cache: true }
      )
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
