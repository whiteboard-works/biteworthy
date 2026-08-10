# frozen_string_literal: true

module Chat
  # Turns stored conversations into what a client renders.
  #
  # Replay and the live stream have to agree, or a page refresh would
  # redraw the turn differently than the user just watched it happen.
  # So the block shapes here mirror the SSE event payloads: text,
  # thinking, tool_use, tool_result.
  #
  # Thinking **signatures are dropped**. They exist so the model can
  # verify its own reasoning on the next request, they are meaningless to
  # a client, and they are the bulkiest thing in the record.
  module Serializer
    RENDERED_BLOCKS = %w[text thinking tool_use tool_result].freeze

    class << self
      def conversation(conversation, messages: false, usage: false)
        payload = {
          id:         conversation.id,
          title:      conversation.title,
          state:      conversation.state,
          mode:       conversation.chat_mode,
          pending:    pending(conversation),
          created_at: conversation.created_at.iso8601,
          updated_at: conversation.updated_at.iso8601
        }
        payload = payload.merge(usage: usage_for(conversation)) if usage
        return payload unless messages

        # `can_undo` rides with the messages rather than being sent
        # unconditionally, and that is a query-count decision: the index
        # endpoint serializes every conversation in the sidebar, and
        # answering "did a write run" for each would load every message
        # of every one. The show endpoint has the rows in hand already,
        # so mapping them first makes the predicate free.
        rendered = conversation.messages.map { |m| message(m) }
        payload.merge(messages: rendered, can_undo: conversation.mutated_since_last_user_message?)
      end

      def message(message)
        {
          id:         message.id,
          role:       message.role,
          position:   message.position,
          # Recorded since the table existed and never sent. `position`
          # orders a transcript; it does not answer "was this five minutes
          # ago or last Tuesday", which is the question a reopened
          # conversation raises.
          created_at: message.created_at.iso8601,
          blocks:     blocks(message)
        }
      end

      private

      # What a turn actually cost, for the person operating the tools.
      #
      # Admin-only, and deliberately so: this is the spend and cache
      # detail that decides whether the chat is affordable, not something
      # a diner has any use for. `api_cost_cents` answers "are we over
      # budget"; the per-round token split answers "where is the money
      # going", which is the question C3 added those columns for.
      # `last_run` is the newest run **that did any work**, not simply the
      # newest row.
      #
      # A turn that fails before its first round still creates a
      # `ConversationRun` — `CompletionJob` acquires the lock, then
      # `enforce_budget!` raises before any HTTP call, so the row is
      # released all-zeros. Reading "the newest run" then reported
      # `0 rounds · 0 in / 0 out · 0.1s` beside a real lifetime cost,
      # which looks like the accounting broke rather than like the turn
      # was refused. Budget rejections, a `heal!` failure, a lost lease,
      # and `nothing_queued` no-op jobs all produce that row.
      #
      # So the numbers come from the last run that has any, and *why the
      # newest one stopped* travels separately in `last_outcome`. Both
      # facts are true and they are about different runs; conflating them
      # was the bug.
      def usage_for(conversation)
        runs    = ConversationRun.where(conversation_id: conversation.id).order(:created_at)
        newest  = runs.last
        run     = runs.where("rounds > 0").last

        {
          cost_cents:   conversation.api_cost_cents,
          last_outcome: newest && { outcome: newest.outcome, state: newest.state },
          last_run: run && {
            # Kept for the run these numbers belong to. `last_outcome`
            # above answers "what happened most recently"; this answers
            # "how did the run these tokens came from end", and after a
            # refused turn they are different runs.
            outcome:            run.outcome,
            state:              run.state,
            rounds:             run.rounds,
            input_tokens:       run.input_tokens,
            output_tokens:      run.output_tokens,
            cache_read_tokens:  run.cache_read_tokens,
            # Stored since C3 and never surfaced, which left the most
            # expensive token class (1.25× input) invisible in the UI.
            cache_write_tokens: run.cache_write_tokens,
            # What *this turn* cost, next to the conversation's lifetime
            # `cost_cents`. Without it the footer put a lifetime total
            # beside per-run token counts and read as a contradiction —
            # "203¢" next to "1,200 in" invites the arithmetic that says
            # 1,200 tokens cost two dollars.
            # Rounded, not ceiled, and matching the `api_cost_cents`
            # generated column's rule — so the per-turn figures roughly
            # sum to the lifetime one instead of over-counting a little
            # on every row.
            cost_cents:         (run.cost_micro_cents / 1_000_000.0).round,
            duration_ms:        run.duration_ms
          }
        }
      end

      # The tool call the loop parked on, so a reloaded page can redraw
      # the confirmation prompt instead of stranding the conversation.
      def pending(conversation)
        return nil unless conversation.awaiting_confirmation?

        parked = conversation.pending_tool_call || {}
        held   = parked["pending"] || {}
        call   = Array(parked["queue"]).first
        return nil if call.nil?

        {
          name:  call["name"],
          input: call["input"],
          # The sentence the tool declared, and the token the answer has to
          # carry back so it can only settle the call it was drawn for.
          prompt:      held["prompt"],
          fingerprint: held["fingerprint"]
        }
      end

      def blocks(message)
        Array(message.content).filter_map do |raw|
          block = raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : {}
          next unless RENDERED_BLOCKS.include?(block["type"])

          render(block)
        end
      end

      def render(block)
        case block["type"]
        when "text"     then { type: "text", text: block["text"] }
        when "thinking" then { type: "thinking", text: block["thinking"] }
        when "tool_use" then { type: "tool_use", id: block["id"], name: block["name"], input: block["input"] }
        else                 tool_result(block)
        end
      end

      def tool_result(block)
        {
          type:        "tool_result",
          tool_use_id: block["tool_use_id"],
          ok:          block["is_error"] != true,
          text:        Array(block["content"]).filter_map { |c| c["text"] }.join("\n").presence
        }
      end
    end
  end
end
