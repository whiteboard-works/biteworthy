require "rails_helper"

# Phase 5.10 — soft-launch waitlist signups.
RSpec.describe WaitlistSignup, type: :model do
  it "accepts a normal email + default source" do
    s = described_class.new(email: "skylar@example.com")
    expect(s).to be_valid
    expect(s.source).to eq("landing")
  end

  it "is invalid without an email" do
    expect(described_class.new(email: nil)).not_to be_valid
  end

  it "rejects obviously malformed emails (no @, no ., whitespace)" do
    %w[skylar nope@ @nope skylar@ @example.com hello\ there@example.com].each do |bad|
      expect(described_class.new(email: bad)).not_to be_valid, "expected '#{bad}' to be rejected"
    end
  end

  it "normalizes email to lowercase + strips whitespace before validation" do
    s = described_class.create!(email: "  Skylar@Example.COM  ")
    expect(s.reload.email).to eq("skylar@example.com")
  end

  it "treats duplicate emails as case-insensitive (citext column)" do
    described_class.create!(email: "skylar@example.com")
    expect {
      # No uniqueness validation on the model — the citext + unique
      # index pair handles dedup at the DB level. The controller
      # uses find_or_initialize_by so end users never see this; the
      # spec just confirms the index does its job.
      described_class.create!(email: "SKYLAR@EXAMPLE.COM")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects unknown source values" do
    s = described_class.new(email: "ok@example.com", source: "twitter_dm")
    expect(s).not_to be_valid
    expect(s.errors[:source]).to be_present
  end

  it "accepts every documented source" do
    %w[landing press footer mobile_app].each do |src|
      sequence = SecureRandom.hex(4)
      s = described_class.new(email: "ok-#{sequence}@example.com", source: src)
      expect(s).to be_valid, "expected source '#{src}' to be valid"
    end
  end
end
