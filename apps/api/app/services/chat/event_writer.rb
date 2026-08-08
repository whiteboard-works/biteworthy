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

      flush! if @buffer.length >= FLUSH_CHARS || (Time.current - @opened) >= FLUSH_SECONDS
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
