require "rails_helper"

# A long conversation re-sends every menu it ever fetched. These pin the
# two things that make dropping them safe — the rows are untouched, and
# the transcript stays byte-identical afterwards — rather than the
# arithmetic, which is a threshold and will move.
RSpec.describe Chat::Compaction do
  let(:user)         { create(:user) }
  let(:conversation) { Conversation.create!(user: user) }

  # Big enough that a handful of them cross the threshold on their own.
  def big_result(id, size: 90_000)
    conversation.append!(
      role: "assistant",
      content: [ { "type" => "tool_use", "id" => id, "name" => "get_menu", "input" => {} } ]
    )
    conversation.append!(
      role: "user",
      content: [ { "type" => "tool_result", "tool_use_id" => id, "content" => "x" * size } ]
    )
  end

  def say(text)
    conversation.append!(role: "user", content: [ { "type" => "text", "text" => text } ])
    conversation.append!(role: "assistant", content: [ { "type" => "text", "text" => text } ])
  end

  # `KEEP_RECENT_MESSAGES` of padding, so anything before it is outside
  # the window and eligible.
  def pad
    (described_class::KEEP_RECENT_MESSAGES / 2).times { |i| say("filler #{i}") }
  end

  def results_sent
    conversation.transcript.flat_map { |m| Array(m[:content]) }
                .select { |b| (b["type"] || b[:type]) == "tool_result" }
  end

  describe "below the threshold" do
    it "leaves a short conversation entirely alone" do
      big_result("t-1", size: 500)
      pad

      expect(described_class.call(conversation).compacted?).to be(false)
      expect(conversation.messages.reload.map(&:compacted_at)).to all(be_nil)
    end
  end

  describe "above the threshold" do
    # Three old results, then the recent window — and a large result
    # *inside* that window. Both halves are load-bearing: without a result
    # in the window nothing distinguishes "keeps the recent ones" from
    # "compacts everything", and without a large one the transcript falls
    # under the threshold after one pass and the second-call guard is
    # never reached.
    before do
      big_result("t-1")
      big_result("t-2")
      big_result("t-3")
      pad
      big_result("t-recent", size: 250_000)
    end

    it "drops the results it is sending and reports what it did" do
      result = described_class.call(conversation)

      expect(result.compacted?).to be(true)
      expect(result.messages).to eq(3)
      expect(result.tokens_saved).to be > 20_000
    end

    # The whole reason this is a marker and not a rewrite. The clients
    # render `conversation.messages`, so editing history to save tokens
    # would delete a person's record of what happened.
    it "leaves the stored rows exactly as they were" do
      described_class.call(conversation)

      stored = conversation.messages.reload.flat_map { |m| Array(m.content) }
                           .select { |b| b["type"] == "tool_result" }
      expect(stored.size).to eq(4)
      expect(stored.map { |b| b["content"] }).to all(match(/\Ax+\z/))
    end

    # An unanswered `tool_use` is rejected by the Messages API, which makes
    # it a permanently dead conversation rather than one cheaper turn.
    it "keeps every result paired to the call it answers" do
      described_class.call(conversation)

      sent  = results_sent
      calls = conversation.transcript.flat_map { |m| Array(m[:content]) }
                          .select { |b| (b["type"] || b[:type]) == "tool_use" }

      expect(sent.map { |b| b["tool_use_id"] }).to match_array(calls.map { |b| b["id"] })
    end

    it "replaces the result with something the model can act on" do
      described_class.call(conversation)

      text = results_sent.first["content"].first["text"]
      expect(text).to eq(described_class::PLACEHOLDER)
      expect(text).to include("Call the tool again")
    end

    # The property the whole design turns on. An elision recomputed per
    # turn would send different bytes as the conversation grew, moving the
    # content above the prompt-cache breakpoint and re-writing the entire
    # transcript on every turn — spending the cost this exists to avoid,
    # forever. Persisting the decision is what makes the second turn free.
    it "sends the same bytes on the next turn" do
      described_class.call(conversation)
      first = conversation.transcript

      reloaded = Conversation.find(conversation.id)
      expect(reloaded.transcript).to eq(first)
    end

    # Still over the threshold afterwards, because the recent window alone
    # is large — so this really does reach the decision rather than
    # short-circuiting on size. Re-marking would re-announce the same
    # elision to the user on every turn for the rest of the conversation.
    it "does not report work when there is nothing left to compact" do
      described_class.call(conversation)

      second = described_class.call(conversation)
      expect(second.compacted?).to be(false)
      expect(second.messages).to eq(0)
    end

    # A scan flow polls `get_scan_status` seven or eight times running.
    # Eliding a result the model is still working from is the one failure
    # mode that costs more than it saves.
    it "never touches the recent window" do
      described_class.call(conversation)

      recent = conversation.messages.reload.last(described_class::KEEP_RECENT_MESSAGES)
      expect(recent.map(&:compacted_at)).to all(be_nil)
      # And says so in the bytes, not only in the marker.
      expect(results_sent.last["content"]).to eq("x" * 250_000)
    end

    # Prose is what the person is reading, and a thinking block's
    # signature is rejected if it is not replayed verbatim.
    it "leaves text and thinking alone" do
      conversation.append!(
        role: "assistant",
        content: [ { "type" => "thinking", "thinking" => "hmm", "signature" => "sig-1" },
                   { "type" => "text", "text" => "Here is the menu." } ]
      )
      described_class.call(conversation)

      blocks = conversation.transcript.flat_map { |m| Array(m[:content]) }
      expect(blocks).to include(hash_including("signature" => "sig-1"))
      expect(blocks.select { |b| (b["type"] || b[:type]) == "text" }.map { |b| b["text"] })
        .to include("Here is the menu.")
    end
  end
end
