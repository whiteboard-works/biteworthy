require "rails_helper"

RSpec.describe Conversation do
  let(:conversation) { create(:conversation) }

  describe "#transcript" do
    it "replays stored blocks verbatim, thinking signatures included" do
      conversation.append!(role: "user", content: [{ type: "text", text: "hi" }])
      conversation.append!(role: "assistant",
                           content: [{ type: "thinking", thinking: "reasoning", signature: "sig-abc" }])

      expect(conversation.transcript.last[:content].first)
        .to include("thinking" => "reasoning", "signature" => "sig-abc")
    end

    # If a turn dies between storing the assistant's tool calls and
    # storing their results — a killed container, a crashed worker — the
    # stored transcript ends on an unanswered tool_use. The Messages API
    # rejects that outright, so without this repair the conversation
    # would be permanently unusable rather than one turn poorer.
    it "answers a tool call the crash left dangling" do
      conversation.append!(role: "user", content: [{ type: "text", text: "scan it" }])
      conversation.append!(role: "assistant", content: [
                             { type: "tool_use", id: "toolu_1", name: "start_menu_scan", input: {} },
                             { type: "tool_use", id: "toolu_2", name: "get_scan_status", input: {} }
                           ])

      repair = conversation.transcript.last

      expect(repair[:role]).to eq("user")
      expect(repair[:content].map { |b| b[:tool_use_id] }).to eq(%w[toolu_1 toolu_2])
      expect(repair[:content]).to all(include(is_error: true))
    end

    it "writes nothing back when it repairs" do
      conversation.append!(role: "assistant",
                           content: [{ type: "tool_use", id: "toolu_1", name: "get_menu", input: {} }])

      expect { conversation.transcript }.not_to change(Message, :count)
    end

    it "leaves an answered turn alone" do
      conversation.append!(role: "assistant",
                           content: [{ type: "tool_use", id: "toolu_1", name: "get_menu", input: {} }])
      conversation.append!(role: "user",
                           content: [{ type: "tool_result", tool_use_id: "toolu_1", content: [] }])

      expect(conversation.transcript.size).to eq(2)
    end
  end

  describe "#append!" do
    it "numbers messages in order" do
      3.times { |i| conversation.append!(role: "user", content: [{ type: "text", text: i.to_s }]) }

      expect(conversation.messages.pluck(:position)).to eq([1, 2, 3])
    end
  end

  describe "#record_usage!" do
    # A ceiling that undercounts is worse than no ceiling, so the chat's
    # model has to have its own rates rather than falling back.
    it "prices the chat model rather than the ingestion default" do
      usage = { "input_tokens" => 1_000_000, "output_tokens" => 0 }

      expect { conversation.record_usage!(usage, model: Chat::AgentLoop::MODEL) }
        .to change { conversation.reload.api_cost_cents }.by(500)
    end
  end
end
