# frozen_string_literal: true

module Chat
  # Stops a long conversation from re-sending every menu it has ever
  # fetched.
  #
  # **What it elides and why that one thing.** Measured on production
  # 2026-08-13, `tool_result` blocks are 59% and 66% of the two largest
  # transcripts — menus and scan payloads, fetched once and replayed on
  # every turn after. Nothing else is close, and nothing else is safe to
  # drop: the assistant's prose is what the person is reading, and a
  # `thinking` block's signature has to replay byte-identically or the
  # request is rejected.
  #
  # **Deterministic, and no model call.** The house rule is that the model
  # is for judgement and code is for everything else — a summarizer here
  # would spend a call, take a minute, and produce something that can be
  # wrong about what it dropped. This drops the *results* and keeps every
  # call that produced them, so the model can still see it asked
  # `get_menu` for Nini's and can ask again if it needs the answer. That
  # is the property that makes elision safe where summarizing is not.
  #
  # **The cost case is narrower than it looks, and worth stating.** With
  # the transcript cached, those stale results are read back at 0.1×, so
  # eliding them saves very little on a warm turn — roughly 6% of its
  # input cost, against a one-off re-write of the compacted prefix at
  # 1.25×. On its own that does not pay back for something like eighteen
  # turns, which is longer than conversations run.
  #
  # It pays on the **cold** ones. The ephemeral cache lasts five minutes
  # and 9 of 28 measured gaps between turns in one conversation are longer
  # than that, so about a third of turns re-write the entire transcript at
  # 1.25×. That is where a 97k-token transcript costs 121k input-equivalent
  # tokens to resume and a compacted one costs 71k. Payback lands around
  # four or five turns, and the ceiling a long conversation dies against
  # stops arriving mid-thought.
  class Compaction
    # Roughly where a transcript starts costing real money to resume.
    # Below it the one-off re-write costs more than the elision saves.
    COMPACT_ABOVE_TOKENS = 60_000

    # How much of the tail is never touched. The curve is flat here:
    # keeping the last 10 messages would elide 43% of all transcript bytes
    # and keeping the last 20 elides 41%, so the extra ten cost two points
    # and buy a much larger margin against the case that actually hurts —
    # eliding a result the model is still working from. A scan flow polls
    # `get_scan_status` seven or eight times in a row; that whole workflow
    # has to stay inside the window.
    KEEP_RECENT_MESSAGES = 20

    # Deliberately says what happened and what to do about it, in the same
    # in-band style as a tool failure. A model that reads "omitted" with no
    # remedy tends to apologise to the user about missing data instead of
    # simply asking for it again.
    PLACEHOLDER = "[Earlier result omitted to keep this conversation within its budget. " \
                  "Call the tool again if you need it.]"

    # Estimated tokens per character. The same 3.6 the prompt-size specs
    # use. A real count is an API round trip per turn to decide something
    # a threshold this soft does not need.
    CHARS_PER_TOKEN = 3.6

    Result = Struct.new(:messages, :tokens_before, :tokens_after, keyword_init: true) do
      def compacted? = messages.positive?
      def tokens_saved = tokens_before - tokens_after
    end

    NONE = Result.new(messages: 0, tokens_before: 0, tokens_after: 0)

    def self.call(conversation) = new(conversation).call

    def initialize(conversation)
      @conversation = conversation
    end

    # Returns what it did, so the caller can tell the user. Marking is the
    # whole write — the content stays put and `transcript` does the rest.
    def call
      stored = @conversation.stored_messages
      before = estimate(stored)
      return NONE if before < COMPACT_ABOVE_TOKENS

      stale = candidates(stored)
      return NONE if stale.empty?

      Message.where(id: stale.map(&:id)).update_all(compacted_at: Time.current)
      stale.each { |message| message.compacted_at = Time.current }

      Result.new(messages: stale.size, tokens_before: before, tokens_after: estimate(stored))
    end

    private

    # Everything outside the recent window that still has results to drop.
    # Already-compacted messages are skipped rather than re-marked, so a
    # second pass over the same conversation is a no-op and cannot report
    # work it did not do.
    def candidates(stored)
      older = stored.first([ stored.size - KEEP_RECENT_MESSAGES, 0 ].max)
      older.select { |message| message.compacted_at.nil? && message.tool_result? }
    end

    # Measured against what is actually sent, which is the point: a
    # compacted message still occupies its placeholder, and the estimate
    # has to agree or the threshold check would loop.
    def estimate(stored)
      chars = stored.sum { |message| @conversation.content_for(message).to_json.length }
      (chars / CHARS_PER_TOKEN).round
    end
  end
end
