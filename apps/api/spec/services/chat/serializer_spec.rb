require "rails_helper"

RSpec.describe Chat::Serializer do
  let(:conversation) { create(:conversation) }

  # History is where a finished turn lives. Without the sentence here, every
  # card the live stream had just labelled "Searching restaurants" redrew as
  # "Did search restaurants" the moment the turn completed.
  it "carries the tool's own sentence on a stored tool call" do
    conversation.append!(role: "assistant", content: [
                           { type: "tool_use", id: "toolu_1", name: "list_cities", input: {} }
                         ])

    block = described_class.conversation(conversation, messages: true)[:messages].first[:blocks].first

    expect(block[:doing]).to eq(Tools::Registry.find("list_cities").running_description_for({}))
    expect(block[:doing]).to be_present
  end

  it "leaves the sentence empty for a tool that no longer exists" do
    conversation.append!(role: "assistant", content: [
                           { type: "tool_use", id: "toolu_1", name: "retired_tool", input: {} }
                         ])

    block = described_class.conversation(conversation, messages: true)[:messages].first[:blocks].first

    expect(block[:doing]).to be_nil
  end
end
