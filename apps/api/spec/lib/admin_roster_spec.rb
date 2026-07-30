require "rails_helper"
require "stringio"

# Guards the roster service behind admin:grant / admin:revoke /
# admin:sync. The tasks run against production, so the contract that
# matters is safety-on-rerun: granting twice is a no-op, unknown
# emails are skipped (never pre-created — a stub would collide with a
# later OAuth signup on the email unique index), and sync reports
# per-email results so a partial roster is visible, not silent.
RSpec.describe Biteworthy::AdminRoster do
  let(:logger) { StringIO.new }
  let(:roster) { described_class.new(logger: logger) }

  describe "#grant" do
    it "flags the user and is idempotent on re-run" do
      user = create(:user)

      expect(roster.grant(user.email)).to eq(:granted)
      expect(user.reload.is_admin).to be true
      expect(roster.grant(user.email)).to eq(:already_admin)
      expect(user.reload.is_admin).to be true
    end

    it "normalizes case/whitespace before lookup (Devise stores downcased)" do
      user = create(:user)

      expect(roster.grant("  #{user.email.upcase}  ")).to eq(:granted)
      expect(user.reload.is_admin).to be true
    end

    it "skips unknown emails without creating a user" do
      expect { expect(roster.grant("nobody@example.com")).to eq(:missing) }
        .not_to change(User, :count)
      expect(logger.string).to include("no account for nobody@example.com")
    end
  end

  describe "#revoke" do
    it "unflags an admin and reports non-admins distinctly" do
      user = create(:user, :admin)

      expect(roster.revoke(user.email)).to eq(:revoked)
      expect(user.reload.is_admin).to be false
      expect(roster.revoke(user.email)).to eq(:not_admin)
    end
  end

  describe "#sync" do
    it "grants every known email and reports missing ones" do
      known = create(:user)

      results = roster.sync(" #{known.email} , ghost@example.com ,")

      expect(results).to eq(known.email => :granted, "ghost@example.com" => :missing)
      expect(known.reload.is_admin).to be true
    end
  end
end
