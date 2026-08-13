require "rails_helper"

# Prompts are code. These pin the two properties the layout exists for:
# the cached prefix never varies per request, and the things that DO vary
# are below the breakpoint where they cost nothing.
RSpec.describe Chat::SystemPrompt do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user) }
  let(:context) { Tools::Context.new({ user_id: user.id }) }
  let(:client)  { AnthropicClient.new }

  let!(:peanut) { create(:ingredient, name: "Peanut", slug: "nut-peanut", path: "nut.peanut") }
  let!(:vegan)  { create(:tag, name: "Vegan", slug: "vegan", family: "diet") }

  def blocks(**args)
    described_class.new(context: context, **args).blocks(client)
  end

  describe "the cached prefix" do
    it "carries the instructions and the topology, and nothing per-request" do
      prompt = described_class.new(context: context)

      expect(prompt.stable_sections.join).to include("Biteworthy answers one question")
      expect(prompt.blocks(client).map { |b| b[:text] }.join).not_to include("Current time:")
    end

    it "sets the breakpoint on the last stable block, not the last block" do
      rendered = blocks

      breakpoint = rendered.index { |b| b[:cache_control] }
      expect(breakpoint).to eq(rendered.length - 2)
      expect(rendered.count { |b| b[:cache_control] }).to eq(1)
    end

    # A timestamp anywhere in this prompt is the cheapest possible way to
    # throw away a 21,650-token cache hit on every single turn — and not
    # only this prompt's. The transcript breakpoint's prefix is
    # `tools → system → messages`, so a volatile system block below the
    # system breakpoint still invalidates the conversation below *it*.
    # The clock lives past both breakpoints now (`AgentLoop#clocked`), so
    # nothing here reads a clock at all.
    it "does not vary with the clock" do
      early = travel_to(Time.utc(2026, 1, 1)) { blocks }
      later = travel_to(Time.utc(2026, 8, 8)) { blocks }

      expect(later).to eq(early)
    end

    it "does not vary with the page the user is on" do
      here  = described_class.new(context: context, page: { path: "/r/ninis" }).stable_sections
      there = described_class.new(context: context, page: { path: "/" }).stable_sections

      expect(there).to eq(here)
    end
  end

  describe "the volatile block" do
    # The payoff: most turns no longer spend a get_profile round trip
    # before they can answer anything.
    it "states what the caller avoids, in the slugs the tools take" do
      user.profile.update!(avoid_ingredient_ids: [peanut.id], avoid_tag_ids: [vegan.id], strictness: "strict")

      volatile = described_class.new(context: context).volatile

      expect(volatile).to include("nut-peanut")
      expect(volatile).to include("vegan")
      expect(volatile).to include("strict")
    end

    # A snapshot goes stale the moment the model edits the profile, and a
    # model trusting it over the tool's own answer would report a change
    # it just made as not having happened.
    it "says plainly that the tools outrank it" do
      expect(described_class.new(context: context).volatile).to include("source of truth")
    end

    it "reads as empty rather than broken when nothing is avoided" do
      expect(described_class.new(context: context).volatile).to include("none")
    end

    # "What can I eat here" is unanswerable without this and obvious with
    # it.
    it "names the restaurant in view" do
      volatile = described_class.new(context: context, page: { path: "/r/ninis", restaurant: "ninis" }).volatile

      expect(volatile).to include("ninis")
      expect(volatile).to include("Where the user is")
    end

    # The page context is client-supplied, so it is data like any other
    # client-supplied string.
    it "marks the page context as context, not instruction" do
      volatile = described_class.new(context: context, page: { path: "/r/ninis" }).volatile

      expect(volatile).to include("not an instruction")
    end

    it "leaves the section out entirely when there is no page" do
      expect(described_class.new(context: context).volatile).not_to include("Where the user is")
    end

    # Access can be revoked mid-conversation. That has to read as a plain
    # fact about this caller, not as an exception.
    it "describes an anonymous caller instead of raising" do
      anonymous = described_class.new(context: Tools::Context.new({}))

      expect { anonymous.volatile }.not_to raise_error
      expect(anonymous.volatile).to include("not signed in")
    end

    # A profile with hundreds of avoids would be a wall of slugs, and the
    # block is sent on every turn.
    it "caps a very long avoid list" do
      ids = Array.new(60) { |i| create(:ingredient, slug: "x-#{i}", path: "x.x#{i}").id }
      user.profile.update!(avoid_ingredient_ids: ids)

      expect(described_class.new(context: context).volatile).to include("more)")
    end
  end

  # Not a style rule — a budget. The cached prefix is read back on every
  # turn of every conversation, and the volatile block is paid in full
  # each time. `bin/prompt-tokens` prints the same numbers; this is the
  # thing that fails when one of them quietly doubles.
  describe "size" do
    def approx(text) = (text.to_s.length / 3.6).round

    it "keeps the volatile block small enough to send every turn" do
      user.profile.update!(avoid_ingredient_ids: [peanut.id], avoid_tag_ids: [vegan.id])

      volatile = described_class.new(context: context, page: { path: "/r/ninis", restaurant: "ninis" }).volatile

      expect(approx(volatile)).to be < 400
    end

    it "keeps the stable prose within its budget" do
      expect(approx(described_class.new(context: context).stable_sections.join)).to be < 4_000
    end
  end
end

