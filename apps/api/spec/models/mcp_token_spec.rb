require "rails_helper"

# Connecting Claude Code today means handing it the same JWT the web app
# uses, which carries everything the account can do — for an admin, the
# taxonomy, the moderation queue, and every user's role. This is the
# credential that can carry less.
RSpec.describe McpToken do
  let(:user) { create(:user) }

  describe ".issue!" do
    it "returns the secret exactly once, and never stores it" do
      token, secret = described_class.issue!(user: user, name: "Claude Code", scopes: ["discovery:read"])

      expect(secret).to start_with(described_class::PREFIX)
      # A leaked database must not be a leaked set of working credentials.
      expect(token.attributes.values.map(&:to_s)).not_to include(secret)
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(secret))
    end

    it "refuses a scope that means nothing" do
      expect { described_class.issue!(user: user, name: "x", scopes: ["menus:teleport"]) }
        .to raise_error(ActiveRecord::RecordInvalid, /unknown/)
    end
  end

  describe ".authenticate" do
    it "resolves a live token" do
      token, secret = described_class.issue!(user: user, name: "Claude Code")

      expect(described_class.authenticate(secret)).to eq(token)
    end

    it "refuses a revoked one" do
      token, secret = described_class.issue!(user: user, name: "Claude Code")
      token.revoke!

      expect(described_class.authenticate(secret)).to be_nil
    end

    it "refuses an expired one" do
      _, secret = described_class.issue!(user: user, name: "Claude Code", expires_at: 1.hour.ago)

      expect(described_class.authenticate(secret)).to be_nil
    end

    # A JWT arriving here must not be mistaken for a missing token, and a
    # random string must not cost a lookup that could match anything.
    it "ignores anything that is not one of ours" do
      expect(described_class.authenticate("eyJhbGciOiJIUzI1NiJ9.abc.def")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
    end
  end

  describe "#note_use!" do
    # A timestamp accurate to the minute answers "is this still in use?";
    # writing a row on every tool call would put a write in front of every
    # read.
    it "records first use and then stops writing" do
      token, = described_class.issue!(user: user, name: "Claude Code")

      token.note_use!
      first = token.reload.last_used_at
      token.note_use!

      expect(first).to be_present
      expect(token.reload.last_used_at).to eq(first)
    end
  end
end
