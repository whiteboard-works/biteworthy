require "rails_helper"

# The two resolve prompts share ResolvePrompt's request-building
# machinery (system blocks + the numbered user message) and differ only
# in their SYSTEM_INSTRUCTIONS. These specs lock the wire-payload shape
# the AnthropicClient is handed — previously only covered indirectly via
# the resolve job specs.
RSpec.describe Ingestion::ResolvePrompt do
  let(:items) do
    [
      { name: "Pad Thai", description: "rice noodles, peanuts", section: "Noodles" },
      { name: "Plain Rice", description: nil, section: nil },
    ]
  end

  describe ".items_block" do
    it "renders a numbered list with section + description, skipping blanks" do
      expect(Ingestion::ResolveIngredientsPrompt.items_block(items)).to eq(
        "[0] Pad Thai (section: Noodles)\n    description: rice noodles, peanuts\n[1] Plain Rice"
      )
    end

    it "accepts string keys as well as symbols" do
      block = Ingestion::ResolveIngredientsPrompt.items_block(
        [{ "name" => "Soup", "section" => "Starters", "description" => "broth" }]
      )
      expect(block).to eq("[0] Soup (section: Starters)\n    description: broth")
    end
  end

  describe ".user_messages" do
    it "wraps the items block in a single user text message" do
      msgs = Ingestion::ResolveIngredientsPrompt.user_messages(items)
      expect(msgs.size).to eq(1)
      expect(msgs.first[:role]).to eq("user")
      text = msgs.first.dig(:content, 0, :text)
      expect(text).to start_with("Resolve ingredients for the following items:")
      expect(text).to include("[0] Pad Thai")
    end

    it "is identical for both prompts (shared machinery)" do
      expect(Ingestion::ResolveTagsPrompt.user_messages(items))
        .to eq(Ingestion::ResolveIngredientsPrompt.user_messages(items))
    end
  end

  describe ".system" do
    # A double records the blocks each prompt hands the client, so we
    # assert the prompt's contribution independent of system_blocks' own
    # transform.
    def captured_blocks_for(prompt_class, catalog)
      client = instance_double(AnthropicClient)
      captured = nil
      allow(client).to receive(:system_blocks) { |*blocks| captured = blocks }
      prompt_class.system(client, catalog)
      captured
    end

    it "sends the subclass instructions first, then the cached catalog" do
      blocks = captured_blocks_for(Ingestion::ResolveIngredientsPrompt, "CATALOG")
      expect(blocks).to eq([
        { text: Ingestion::ResolveIngredientsPrompt::SYSTEM_INSTRUCTIONS },
        { text: "CATALOG", cache: true },
      ])
    end

    it "resolves SYSTEM_INSTRUCTIONS per subclass (tags ≠ ingredients)" do
      tag_blocks = captured_blocks_for(Ingestion::ResolveTagsPrompt, "TAGS")
      expect(tag_blocks.first[:text]).to eq(Ingestion::ResolveTagsPrompt::SYSTEM_INSTRUCTIONS)
      expect(tag_blocks.first[:text]).to include("tags")
      expect(Ingestion::ResolveTagsPrompt::SYSTEM_INSTRUCTIONS)
        .not_to eq(Ingestion::ResolveIngredientsPrompt::SYSTEM_INSTRUCTIONS)
    end
  end
end
