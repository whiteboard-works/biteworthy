require "rails_helper"

# Who is calling, resolved once per request from the MCP server_context.
RSpec.describe Tools::Context do
  # The distinction the scope fail-open could not draw. An empty grant used
  # to satisfy every check, so a credential that had been given nothing was
  # indistinguishable from a caller that had no credential at all — and the
  # two need opposite answers. Everything else in this file exists to keep
  # those two shapes from collapsing back into one.
  describe "#scopes" do
    it "reads an omitted key as nothing narrowing this call" do
      expect(described_class.new({ user_id: "x" }).scopes).to eq([ Tools::Scopes::ALL ])
      expect(described_class.new({}).scopes).to eq([ Tools::Scopes::ALL ])
      expect(described_class.new(nil).scopes).to eq([ Tools::Scopes::ALL ])
    end

    # A credential *was* consulted and granted nothing. That is a refusal,
    # not an absence, and it must not round back up to full authority.
    it "reads a stated empty grant as a refusal" do
      context = described_class.new({ user_id: "x", scopes: [] })

      expect(context.scopes).to eq([])
      expect(Tools::Scopes.satisfied?(context.scopes, "taxonomy:write")).to be(false)
    end

    it "keeps a narrow grant exactly as granted" do
      expect(described_class.new({ scopes: [ "profile:read" ] }).scopes).to eq([ "profile:read" ])
    end
  end
end
