require "rails_helper"

# A ticket stands in for the session on one request. It has to name its
# user and nobody else, and stop working on its own.
RSpec.describe Attachments::UploadTicket do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it "round-trips the user it was issued to" do
    expect(described_class.user_for(described_class.issue(user))).to eq(user)
  end

  it "expires" do
    ticket = described_class.issue(user)

    travel(described_class::TTL + 1.second) do
      expect(described_class.user_for(ticket)).to be_nil
    end
  end

  it "rejects a tampered ticket" do
    ticket = described_class.issue(user)

    expect(described_class.user_for(ticket.sub(/\A../, "zz"))).to be_nil
    expect(described_class.user_for("")).to be_nil
    expect(described_class.user_for(nil)).to be_nil
  end

  # Same key, different purpose: a token minted elsewhere in the app must
  # not open the upload door.
  it "rejects a message signed for another purpose" do
    other = described_class.verifier.generate({ "user_id" => user.id }, purpose: :something_else)

    expect(described_class.user_for(other)).to be_nil
  end

  it "answers nil for a user who no longer exists" do
    ticket = described_class.issue(user)
    user.destroy!

    expect(described_class.user_for(ticket)).to be_nil
  end
end
