# frozen_string_literal: true

module Chat
  # Turns the loop's `on_event` callback into rows.
  #
  # The loop emits a delta per token. Writing a row each would be tens of
  # thousands of inserts for one answer and a table nobody can read, so
  # deltas of the same kind are accumulated and flushed on whichever comes
  # first: enough characters to be worth sending, enough time that the
  # reader would notice the gap, or a different kind of event arriving.
  #
  # Everything else — tool calls, tool results, the terminal event — is
  # written straight through, because those are the things a client draws
  # a card for and none of them are frequent.
  class EventWriter
    # Roughly a line of text. Small enough that prose still appears to
    # arrive as it is written, large enough that a paragraph is a handful
    # of rows rather than hundreds.
    FLUSH_CHARS   = 80
    FLUSH_SECONDS = 0.15

    DELTA_TYPES = %w[text_delta thinking_delta].freeze

    def initialize(run)
      @run     = run
      @kind    = nil
      @buffer  = +""
      @opened  = nil
    end

    def call(payload)
      type = payload[:type].to_s

      unless DELTA_TYPES.include?(type)
        flush!
        ConversationEvent.append!(@run, payload)
        return
      end

      flush! if @kind && @kind != type
      @kind    ||= type
      @opened  ||= Time.current
      @buffer << payload[:text].to_s

      # `flush: true` is for a caller that knows it is about to block.
      #
      # Both ordinary triggers are evaluated *here*, when the next delta
      # arrives — there is no timer — so a short delta with nothing behind
      # it sits in the buffer indefinitely. That is harmless while tokens
      # keep coming and useless exactly when they stop, which is the case
      # `AgentLoop::RECHECKING` exists for: a 46-character notice emitted
      # immediately before a repair that can take minutes would otherwise
      # be written out only once the repair returned, i.e. after the wait
      # it was meant to explain.
      flush! if payload[:flush] || @buffer.length >= FLUSH_CHARS || (Time.current - @opened) >= FLUSH_SECONDS
    end

    def flush!
      return if @kind.nil? || @buffer.empty?

      ConversationEvent.append!(@run, { type: @kind, text: @buffer })
      @kind   = nil
      @buffer = +""
      @opened = nil
    end
  end
end
