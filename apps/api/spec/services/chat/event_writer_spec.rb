require "rails_helper"

# The writer had no spec at all until its buffering caused a real bug, so
# these pin the contract rather than the implementation: what a reader
# ends up seeing, and when.
#
# The thing worth internalising is that **there is no timer**. Both
# ordinary flush triggers are evaluated when the *next* delta arrives, so
# a short delta with nothing behind it is not "flushed a moment later" —
# it is not flushed at all until something else happens.
RSpec.describe Chat::EventWriter do
  let(:user)         { create(:user) }
  let(:conversation) { Conversation.create!(user: user) }
  let(:run)          { ConversationRun.acquire(conversation) }

  subject(:writer) { described_class.new(run) }

  def written = ConversationEvent.where(conversation_id: conversation.id).order(:position).map(&:payload)
  def texts   = written.filter_map { |p| p["text"] }

  it "coalesces a run of deltas into one row rather than one per token" do
    5.times { writer.call(type: "text_delta", text: "word ") }
    writer.flush!

    expect(written.size).to eq(1)
    expect(texts.first).to eq("word " * 5)
  end

  it "writes a full line out without waiting" do
    writer.call(type: "text_delta", text: "x" * described_class::FLUSH_CHARS)

    expect(texts.join).to eq("x" * described_class::FLUSH_CHARS)
  end

  it "writes anything that is not a delta straight through" do
    writer.call(type: "text_delta", text: "partial")
    writer.call(type: "tool_use", name: "get_menu")

    expect(written.map { |p| p["type"] }).to eq(%w[text_delta tool_use])
  end

  it "does not mix thinking into a text buffer" do
    writer.call(type: "text_delta", text: "answer")
    writer.call(type: "thinking_delta", text: "hmm")
    writer.flush!

    expect(written.map { |p| p["type"] }).to eq(%w[text_delta thinking_delta])
  end

  describe "a caller that is about to block" do
    # The regression that made `flush:` necessary. `AgentLoop::RECHECKING`
    # is 46 characters and the repair behind it can take minutes, so on
    # the ordinary triggers it would reach the reader *after* the wait it
    # exists to explain — which is the same as not sending it.
    it "leaves a short delta buffered when nothing follows it" do
      writer.call(type: "text_delta", text: "short")

      expect(written).to be_empty
    end

    it "sends it immediately when the caller asks" do
      writer.call(type: "text_delta", text: "short", flush: true)

      expect(texts.join).to eq("short")
    end

    # The notice rides on the end of whatever was already buffered, so
    # asking to flush must not drop the answer it is appended to.
    it "carries the buffered answer out with it" do
      writer.call(type: "text_delta", text: "the al pastor works")
      writer.call(type: "text_delta", text: Chat::AgentLoop::RECHECKING, flush: true)

      expect(texts.join).to eq("the al pastor works#{Chat::AgentLoop::RECHECKING}")
    end
  end
end
