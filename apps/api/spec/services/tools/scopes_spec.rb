require "rails_helper"

# What a credential is allowed to do, in the vocabulary of tool domains.
#
# The vocabulary is derived from the registry rather than listed, so a new
# domain cannot ship without a scope for it — the same discipline that
# keeps the topology map honest.
RSpec.describe Tools::Scopes do
  it "covers every registered domain, read and write" do
    Tools::Registry::DOMAINS.each_key do |domain|
      expect(described_class.available).to include("#{domain}:read", "#{domain}:write")
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

  describe ".satisfied?" do
    # Every credential issued before scopes existed carries none. Treating
    # that as "denied" would lock out every working integration; treating
    # it as "unrestricted" is what it has always been.
    it "treats an unscoped credential as unrestricted" do
      expect(described_class.satisfied?([], "users:write")).to be(true)
      expect(described_class.satisfied?(nil, "users:write")).to be(true)
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
