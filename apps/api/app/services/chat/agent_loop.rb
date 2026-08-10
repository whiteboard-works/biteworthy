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
  #     a time. How much of that a person has agreed to up front is the
  #     turn's `mode`; `Chat::ModePolicy` owns the four answers, and the
  #     tool catalogue is the same under all of them.
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
    # A wall against a model that loops on a failing tool. Twelve was
    # "comfortably past the longest real workflow (the scan flow is
    # seven)" — and then real turns started arriving at eleven and twelve
    # rounds, which is not comfortable, it is the wall. Twenty keeps the
    # runaway guard while leaving the honest long turn room to finish.
    MAX_ITERATIONS = 20
    # Super admins get headroom rather than no wall at all — the turn
    # deadline still bounds the turn, and an unbounded `loop` here would
    # make a runaway cost real money before that fired.
    SUPER_ADMIN_MAX_ITERATIONS = 60

    # The other wall, because rounds are not time. One round may sit for
    # the full `ANTHROPIC_READ_TIMEOUT` (240s), and `tick!` renews the
    # lease at every step — so a long run of slow rounds holds a
    # conversation for the better part of an hour while every watchdog we
    # have reads healthy.
    #
    # Was five minutes, described as "several times the ~60s a real turn
    # takes". Real turns are not 60s: the observed ones run eleven and
    # twelve rounds, and at that length five minutes is the thing ending
    # the turn rather than a guard against a stuck one. Ten.
    TURN_DEADLINE_SECONDS_DEFAULT = 600
    # Raised, not removed, for the super tier — and that raise re-admits
    # a bounded version of what the deadline prevents. `caller_is_super_admin?`
    # spells out why 30 minutes is an acceptable trade and no bound is not.
    SUPER_ADMIN_TURN_DEADLINE_SECONDS_DEFAULT = 1_800

    # $2 was set when a turn was believed to cost ~8.5¢, which made it
    # about twenty turns. Measured turns run 17–95¢, so it was really
    # two to five — a conversation died mid-thought and the person was
    # told to start a new one, losing the context that made it expensive
    # in the first place. C9's transcript caching cuts the long-turn cost
    # substantially, and $10 is the ceiling for what that leaves: enough
    # that a real working session finishes, low enough to still catch a
    # loop.
    PER_CONVERSATION_CEILING_CENTS_DEFAULT = 1_000 # $10
    DAILY_CEILING_CENTS_DEFAULT            = 5_000 # $50/day across all non-admin chat

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
    # `mode` is the chat mode the turn was *sent* under, carried in the
    # queued payload rather than read off the conversation here. A mode
    # picked after the send belongs to the next turn: someone who switches
    # to planning while a turn is mid-flight is telling us what to do next,
    # not retroactively withdrawing consent for the calls already running.
    def initialize(conversation, client: nil, public_host: nil, on_event: nil, run: nil, page: nil, mode: nil)
      @conversation = conversation
      @client       = client || AnthropicClient.new(model: MODEL)
      @public_host  = public_host
      @on_event     = on_event
      @injected_run = run
      @page         = page
      @mode         = ModePolicy.resolve(mode || conversation.chat_mode)
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
      #
      # Deliberately the one early exit that does NOT halt: writing a
      # message or answering orphans here would edit a transcript another
      # run is actively appending to.
      Rails.logger.warn("[chat] run #{@run&.id} lost its lease on conversation #{@conversation.id}")
      Result.new(state: :error, error: "That turn was interrupted. Try again.")
    rescue ArgumentError
      # A caller bug, not a runtime failure — the controller settles a
      # pending confirmation and checks for text before it ever enqueues,
      # so reaching one of `perform`'s guards means our own code is wrong.
      # Dressing it as an outage the user should retry would bury it.
      raise
    rescue StandardError => e
      Rails.logger.error("[chat] conversation #{@conversation.id} crashed: #{e.class}: #{e.message}")
      Rails.error.report(e, handled: true, context: { conversation_id: @conversation.id })
      crashed
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
    #
    # Every way a turn can end goes through here, and that is the point.
    # The alternative — returning a bare error `Result` — told the person
    # watching and nobody else: the reason lived only in an SSE event, and
    # `Chat::Serializer` builds a conversation from `messages`, so a
    # reload showed their own question with nothing after it.
    #
    # Not an alternation fix, though it was written up as one. The
    # Messages API accepts consecutive same-role messages (probed on
    # `claude-opus-5`: both `user, user` and `assistant, assistant` return
    # normally). What it refuses is a transcript that *ends* on an
    # assistant turn, and `Conversation#repair_for` already covers that.
    #
    # `orphan_reason` is what the *model* reads next turn, and it is
    # deliberately not the sentence the user reads. A call that never ran
    # because someone hit stop and one that never ran because we crashed
    # are different facts; answering both with "stopped" is a transcript
    # that lies to the next turn. Only stop and a raise inside the queue
    # walk can actually strand a call — the budget, deadline and upstream
    # checks all sit at the top of a round, by which point the previous
    # round's results are already stored.
    def halt(message, orphan_reason: "Stopped before this ran. Nothing happened.")
      @conversation.answer_orphans!(orphan_reason)
      @conversation.append!(role: "assistant", content: [{ type: "text", text: message }])
      @conversation.update!(state: "active", pending_tool_call: nil)
      Result.new(state: :error, error: message)
    end

    # The floor under everything we did not name. Every other exit above
    # describes a failure we understood; this one runs when we did not,
    # and the worst it may leave behind is a person looking at their own
    # message with no reply and no explanation.
    #
    # The persist is best-effort because the exception being recovered
    # from may be the database itself, and a floor that raises while
    # laying itself down is not a floor. The terminal event fires either
    # way — #583 means a client whose run has been released will close its
    # stream regardless, so without this it closes on silence and redraws
    # a turn that simply stopped.
    #
    # Returns rather than re-raising: `finish_run`'s ensure already books
    # the run as `crashed`, and letting it out would fail the Solid Queue
    # job, whose retry re-enters `perform` and pops the *next* queued turn
    # — losing this one's text while the drain loop was going to reach it
    # anyway.
    def crashed
      message = "Sorry — something went wrong on my end and I stopped partway through. " \
                "Try again, and start a new chat if it keeps happening."
      begin
        halt(message, orphan_reason: "The turn failed before this ran. Nothing happened.")
      rescue StandardError => e
        Rails.logger.error(
          "[chat] conversation #{@conversation.id} could not record its own crash: #{e.class}: #{e.message}"
        )
      end
      Result.new(state: :error, error: message).tap { |result| emit_terminal(result) }
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
      # `enforce_budget!` already writes the sentence: it names the
      # ceiling, the spend, and what to do — "start a new one" for the
      # per-conversation wall, "try again tomorrow" for the daily one.
      # Those are different instructions and a generic handoff line
      # appended here would be wrong for the second, so the message rides
      # through untouched. What changes is that it gets written down.
      halt(e.message, orphan_reason: "The conversation hit its spend limit before this ran. Nothing happened.")
    rescue AnthropicClient::ApiError, AnthropicClient::Stream::IncompleteError => e
      # Upstream trouble, not a bug in us — say so plainly and leave the
      # conversation usable so the user can just try again.
      Rails.logger.error("[chat] conversation #{@conversation.id} upstream failure: #{e.class}: #{e.message}")
      halt("The assistant is unavailable right now. Try again in a moment.",
           orphan_reason: "The assistant became unavailable before this ran. Nothing happened.")
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

      # Deliberately not re-checked against the mode. Someone who switched
      # to planning and then answered this prompt has given two
      # instructions, and the one naming this exact call — bound to its
      # fingerprint — is the more specific of the two.
      #
      # The rest of the queue still runs through the gate, and through the
      # mode with it: confirming one destructive call does not
      # pre-authorize the next.
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

      # Halted rather than returned, for the same reason the deadline is:
      # the last round appended its `tool_result` message, so a bare
      # return would leave the transcript ending on a `user` role.
      halt(
        "I worked through #{rounds} steps without getting to an answer, so I stopped. " \
        "Ask me for a narrower piece of it and I'll pick it up from here.",
        orphan_reason: "The turn hit its #{rounds}-step limit before this ran. Nothing happened."
      )
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
      halt("That took too long, so I stopped it. Nothing further ran — ask again to pick it up.",
           orphan_reason: "The turn ran out of time before this ran. Nothing happened.")
    end

    # Walks the turn's tool calls, stopping at the first that needs a
    # human. Returns an :awaiting_confirmation Result when it parks, or
    # nil-state :continue once every call in the turn is answered.
    def continue_queue(queue, results)
      queue.each_with_index do |call, index|
        case decide(call)
        when :park
          return Result.new(state: :awaiting_confirmation, pending: park(results, queue.drop(index)))
        when :refuse
          # Ticked like a real call even though nothing runs. `tick!` is
          # what renews the lease and notices the stop button, and a model
          # that answers a planning turn with twenty writes would
          # otherwise spend the whole turn deaf to Stop.
          tick!
          # Narrated like any other call, and deliberately so: the user
          # asked for a plan and what the model reached for on the way is
          # part of the answer. The refusal is the tool's own result, so
          # the transcript replays identically to what was watched live.
          emit(type: "tool_use", name: call["name"], input: call["input"], doing: doing(call))
          emit(type: "tool_result", name: call["name"], ok: false)
          results << refusal(call)
        else
          emit(type: "tool_use", name: call["name"], input: call["input"], doing: doing(call))
          result = execute(call, confirmation: standing_grant_for(call))
          emit(type: "tool_result", name: call["name"], ok: !result[:is_error])
          results << result
        end
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
      tool        = tool_for(call)
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
      tool_for(call)&.running_description_for(arguments_for(call))
    end

    # :run, :park, or :refuse. The mode owns the decision; this only
    # resolves the call into what the policy needs to read.
    #
    # `skip_confirmations` rides into the policy rather than short-
    # circuiting in front of it, because it does not answer every
    # question the policy asks: it is a standing yes to *parking*, and
    # planning mode's refusal is not a confirmation question at all. One
    # place decides which beats which.
    #
    # It is consulted on this side at all — `Tools::Base#confirmation_gate`
    # checks it too — because the chat door parks *before* the tool
    # boundary is reached, and without it the turn would stop and wait for
    # an answer the gate below would then have waved through.
    def decide(call)
      policy.decide(tool_for(call), arguments_for(call))
    end

    def policy
      @policy ||= ModePolicy.new(@mode, skip_confirmations: context.skip_confirmations?)
    end

    def refusal(call)
      tool_result(call, { error: "planning_mode", message: ModePolicy::REFUSAL }, error: true)
    end

    # Resolved against what this caller can *see*, not the whole
    # registry. `docs/mcp.md` promises that a tool outside a caller's
    # audience or scope answers "tool not found" rather than a scope
    # complaint — existence is itself the secret — and the MCP door keeps
    # that promise by handing the gem `Registry.for(context)`. This door
    # was calling `Registry.find`, so an admin tool named exactly came
    # back `forbidden: "You do not have permission to do that."`, which
    # confirms it exists; named destructively it reached `decide` first
    # and *parked*, asking someone to approve a call that could only fail.
    # Two front doors, two answers to the same question, and the one that
    # leaked is the one pointed at a model.
    #
    # A hash rather than a scan: `for(context)` is memoized on the
    # context, but the loop asks three times per call and the old
    # `Registry.find` walked all 44 tools each time.
    def tool_for(call) = visible_tools[call["name"]]

    def visible_tools
      @visible_tools ||= Tools::Registry.for(context).index_by(&:name_value)
    end

    # A near miss is the likely shape of this failure, not an invented
    # capability: `ToolCatalog` keeps three domains resident and defers
    # the other 41 schemas behind tool search, so the model is usually
    # working from a name it read once in a search result. "No tool named
    # X" costs a round at best, and at worst becomes "Biteworthy can't do
    # that" — a false limitation the person then carries away with them.
    #
    # Candidates come from `Registry.for(context)`, never `all`. The
    # filtered set is what this caller can see, and offering
    # `set_user_role` to a non-admin would leak the admin surface through
    # an error string — the one thing `docs/mcp.md` promises an invisible
    # tool never does. `for` is memoized on the context, so this is free.
    def unknown_tool(call)
      name       = call["name"].to_s
      suggestion = DidYouMean::SpellChecker
                   .new(dictionary: visible_tools.keys)
                   .correct(name).first

      message =
        if suggestion
          "No tool named #{name}. Did you mean #{suggestion}? Call it again with the corrected name."
        else
          "No tool named #{name}. Search for the capability with " \
          "#{ToolCatalog::SEARCH_TOOL[:name]} before telling the user it is unsupported."
        end

      tool_result(call, { error: "unknown_tool", message: message }, error: true)
    end

    # The mode's answer, in the form `Tools::Base` can verify.
    #
    # `accept_edits` and `auto` say run to calls that manual would have
    # parked — but the tool boundary re-checks the gate on the way
    # through, and it has to: MCP has no modes, so `confirmation_gate` is
    # the only door on that side and must not learn to trust its caller.
    # A mode is therefore a standing *answer*, not a bypass, and it
    # travels as the same grant `resume` mints when a person answers one
    # call in person.
    #
    # nil for anything that was not gated to begin with, which is nearly
    # every call — minting one per tool call would spend a signature on
    # `get_menu`.
    def standing_grant_for(call)
      return nil unless ToolCatalog.confirm_required?(tool_for(call), arguments_for(call))

      grant_for(call)
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
      tool = tool_for(call)
      return unknown_tool(call) if tool.nil?

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
    # rebuilding it for each of up to twenty rounds bought nothing: the
    # catalogue re-rendered 44 JSON schemas, the topology walked the
    # registry twice more, and the profile snapshot went back to Postgres
    # — all to produce the bytes the cache is keyed on.
    def model_args
      {
        model:      MODEL,
        max_tokens: MAX_TOKENS,
        system:     system_prompt,
        messages:   cacheable(@conversation.transcript),
        tools:      tool_definitions,
        thinking:   { type: "adaptive" }
      }
    end

    # The transcript is the expensive half of a turn and it was not cached
    # at all.
    #
    # C5 put the one `cache_control` breakpoint on the last system block,
    # which caches tools + instructions + topology — stable, and worth it.
    # Everything after that breakpoint is re-read at full input price on
    # every round, and "everything after" is the conversation: the user's
    # messages, the assistant's, and every tool result, including a whole
    # menu from `get_menu`. A round adds a few thousand tokens and then
    # pays for all of them again on each later round, so the cost of a
    # turn grows with the square of its length. Measured on a real
    # eleven-round turn: 167,655 input tokens for a transcript that was
    # only ever a few thousand tokens long, and 95¢.
    #
    # A breakpoint on the last block makes the whole conversation so far a
    # cached prefix for the next round: written once at 1.25×, read after
    # that at 0.1×. Rolling it forward each round is the documented
    # multi-turn pattern — earlier breakpoints stay valid read points, so
    # hits accrue as the conversation grows rather than being rewritten.
    #
    # Two things this relies on, both true here and neither obvious:
    #
    #   * **The last message is always a `user` one at call time.** `drive`
    #     calls the model at the top of its loop and appends the assistant
    #     reply after, so a breakpoint never lands on a `thinking` block —
    #     whose signature must replay byte-identically. The guard below
    #     enforces it anyway rather than trusting the loop's shape to stay
    #     that way.
    #   * **A breakpoint only looks back 20 content blocks** for a prior
    #     entry. A round appends one assistant message and one user
    #     message — a handful of blocks — so consecutive requests are well
    #     inside that. A single round that fanned out to more than ~20
    #     parallel tool calls would silently miss and pay full price for
    #     that round; it would still be correct, just not cached.
    NON_CACHEABLE_BLOCKS = %w[thinking redacted_thinking].freeze

    def cacheable(turns)
      last   = turns.last
      blocks = Array(last && last[:content])
      tail   = blocks.last
      # Bailing out is correct but invisible — an uncached round costs
      # nothing but money, so it shows up in the bill and nowhere else.
      return uncacheable(turns, "last block is #{tail.class}") unless tail.is_a?(Hash)

      type = tail["type"] || tail[:type]
      return uncacheable(turns, "last block is #{type}") if NON_CACHEABLE_BLOCKS.include?(type)

      # Copied rather than mutated: `transcript` hands back the loaded
      # records' own jsonb, and marking it in place would write a
      # `cache_control` key into the stored message on the next save.
      marked = blocks[0..-2] + [ tail.merge(cache_control: { type: "ephemeral" }) ]
      turns[0..-2] + [ last.merge(content: marked) ]
    end

    def uncacheable(turns, why)
      Rails.logger.info("[chat] transcript not cached for conversation #{@conversation.id}: #{why}")
      turns
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
      @system_prompt ||= SystemPrompt.new(context: context, page: @page, mode: @mode).blocks(@client)
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
    # The wall-clock deadline is **raised, not cleared** — 600s to 1,800s
    # — and the honest reading of that is that it re-admits a smaller
    # version of the problem the deadline was added for: a wedged turn
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
    # Summed over the **runs** that happened today, not over conversations
    # *created* today.
    #
    # The old form charged a conversation's whole lifetime spend to its
    # creation date, so a conversation opened yesterday and continued
    # today contributed nothing to today's total. Chats are meant to
    # survive across sessions — there is a history sidebar — so that is
    # the normal case, not an edge one, and raising the per-conversation
    # ceiling to $10 turned it from a $2 hole into a $10 one *per*
    # long-lived conversation. A run belongs unambiguously to the day it
    # ran on.
    #
    # Admins are excluded from the **sum**, not merely from the check.
    # `enforce_budget!` already lets them past this ceiling and the
    # constant calls it "$50/day across all non-admin chat" — but the
    # aggregate counted everyone, so an operator driving the tools for an
    # afternoon could fill the community's budget and lock out every
    # ordinary user while staying exempt themselves. Exempt from a
    # ceiling and able to fill it is the wrong pair.
    # `.where(users: { is_admin: false })` is how `DashboardsController`
    # and `Admin::IngestionRunsController` already isolate community
    # traffic; this is the same rule applied where it was missing.
    def daily_spend_micro
      unless defined?(@daily_spend_baseline)
        @daily_spend_baseline = ConversationRun
                                .where(created_at: Time.current.utc.beginning_of_day..)
                                .joins(conversation: :user)
                                .where(users: { is_admin: false })
                                .sum(:cost_micro_cents)
        @own_spend_baseline   = @conversation.api_cost_micro_cents
      end

      # This turn's own accrual added back on top of the snapshot, so the
      # round that crosses the ceiling still trips it — a runaway loop is
      # what the ceiling is for, and it is the one spender a baseline read
      # once per turn could miss by a lot.
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
