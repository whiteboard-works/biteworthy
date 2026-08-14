require "rails_helper"

# What a credential is allowed to do, in the vocabulary of tool domains.
#
# The vocabulary is derived from the registry rather than listed, so a new
# domain cannot ship without a scope for it — the same discipline that
# keeps the topology map honest.
RSpec.describe Tools::Scopes do
  it "covers every gated domain, read and write" do
    (Tools::Registry::DOMAINS.keys - described_class::UNGATED_DOMAINS).each do |domain|
      expect(described_class.available).to include("#{domain}:read", "#{domain}:write")
    end
  end

  # Offering a scope that nothing checks would ask someone on a consent
  # screen for permission that means nothing. `meta` is the server
  # describing itself, already filtered to the caller.
  it "offers no scope for a domain nothing gates" do
    described_class::UNGATED_DOMAINS.each do |domain|
      expect(described_class.available.grep(/\A#{domain}:/)).to be_empty
      expect(described_class.valid?("#{domain}:read")).to be(false)
    end
  end

  # The split follows the annotation a tool already carries, so it cannot
  # drift from what the tool actually does.
  it "reads a tool's requirement off its own read_only_hint" do
    expect(described_class.for_tool(Tools::Discovery::GetMenu)).to eq("discovery:read")
    expect(described_class.for_tool(Tools::Users::SetUserRole)).to eq("users:write")
  end

  # A class the registry does not know — an anonymous subclass in a spec —
  # is not something a scope can meaningfully protect, and asking must not
  # raise.
  it "returns nothing for a tool the registry does not know" do
    expect { described_class.for_tool(Class.new(Tools::Base)) }.not_to raise_error
    expect(described_class.for_tool(Class.new(Tools::Base))).to be_nil
  end

  # An OAuth consent screen shows these sentences. A scope with no
  # description would render as "profile:write", which is not something a
  # person can agree to or refuse on the merits.
  describe ".describe" do
    it "has a sentence for every scope it can grant" do
      expect(described_class.available.map { |s| described_class.describe(s) }).to all(match(/\A[A-Z]/))
    end

    it "says plainly which grants can change things" do
      expect(described_class.describe("profile:read")).to start_with("Read ")
      expect(described_class.describe("profile:write")).to start_with("Read and change ")
    end

    # A domain added without a description must not 500 someone
    # mid-authorization; the spec above is what catches the omission.
    it "falls back to the raw scope rather than raising" do
      expect(described_class.describe("nonsense:read")).to eq("nonsense:read")
    end
  end

  describe ".satisfied?" do
    # The fail-open this replaced. An empty grant used to satisfy every
    # check, so the vocabulary had no way to say "nothing" — and any path
    # that produced an empty list escalated silently to all thirteen gated
    # domains. `McpTokensController` reached it with two blank strings.
    it "refuses a credential that was granted nothing" do
      expect(described_class.satisfied?([], "users:write")).to be(false)
      expect(described_class.satisfied?(nil, "users:write")).to be(false)
    end

    # The inversion that gave it away: asking for less than the minimum
    # used to get you more than the maximum.
    it "never lets an empty grant outrank a narrow one" do
      narrow = described_class.satisfied?(["profile:read"], "taxonomy:write")

      expect(described_class.satisfied?([], "taxonomy:write")).to eq(narrow)
    end

    # Full authority still exists — it is spelled, not implied.
    it "honours the wildcard as the way to say everything" do
      expect(described_class.satisfied?([described_class::ALL], "users:write")).to be(true)
    end

    # An ungated domain is reachable by a caller granted nothing at all:
    # `meta` is the server describing itself, already filtered to whoever
    # is asking, and gating it would hide the map from a client that never
    # thought to ask for it.
    it "still lets a nothing-grant reach what no scope gates" do
      expect(described_class.satisfied?([], nil)).to be(true)
    end

    it "honours an exact grant" do
      expect(described_class.satisfied?(["discovery:read"], "discovery:read")).to be(true)
      expect(described_class.satisfied?(["discovery:read"], "users:write")).to be(false)
    end

    # Permission to edit a menu but not to look at one would be nonsense.
    it "lets write imply read on the same domain" do
      expect(described_class.satisfied?(["items:write"], "items:read")).to be(true)
    end

    # The reverse must not hold — that is the entire point.
    it "never lets read imply write" do
      expect(described_class.satisfied?(["items:read"], "items:write")).to be(false)
    end

    it "does not leak across domains" do
      expect(described_class.satisfied?(["discovery:write"], "taxonomy:read")).to be(false)
    end
  end
end
