require "rails_helper"

RSpec.describe RestaurantClaim do
  let(:owner)      { create(:user, email: "owner@durangosmelter.com") }
  let(:restaurant) { create(:restaurant, :published, name: "Durango Smelter Pub", website: "https://durangosmelter.com") }

  describe ".email_matches_website?" do
    it "matches when domains are identical" do
      expect(described_class.email_matches_website?("a@durangosmelter.com", "https://durangosmelter.com")).to be(true)
    end

    it "strips a leading www. on the website host" do
      expect(described_class.email_matches_website?("a@durangosmelter.com", "https://www.durangosmelter.com")).to be(true)
    end

    it "is case-insensitive" do
      expect(described_class.email_matches_website?("A@DurangoSmelter.com", "https://durangosmelter.com")).to be(true)
    end

    it "returns false for a mismatch" do
      expect(described_class.email_matches_website?("a@gmail.com", "https://durangosmelter.com")).to be(false)
    end

    it "returns false when website is blank" do
      expect(described_class.email_matches_website?("a@x.com", nil)).to be(false)
    end

    it "returns false on garbage URLs" do
      expect(described_class.email_matches_website?("a@x.com", "not a url at all")).to be(false)
    end

    it "returns false on missing email domain" do
      expect(described_class.email_matches_website?("noatsign", "https://x.com")).to be(false)
    end
  end

  describe ".request_claim" do
    it "creates a Suggestion(kind: 'claim') with token + email + expiry" do
      expect {
        described_class.request_claim(restaurant: restaurant, requester: owner, email: "owner@durangosmelter.com")
      }.to change(Suggestion, :count).by(1)

      suggestion = Suggestion.last
      expect(suggestion.kind).to eq("claim")
      expect(suggestion.subject).to eq(restaurant)
      expect(suggestion.user).to eq(owner)
      expect(suggestion.payload["email"]).to eq("owner@durangosmelter.com")
      expect(suggestion.payload["token"]).to be_present
      expect(suggestion.payload["expires_at"]).to be_present
      expect(suggestion.payload["auto_acceptable"]).to be(true)
    end

    it "marks auto_acceptable: false on a domain mismatch (still creates the Suggestion)" do
      result = described_class.request_claim(restaurant: restaurant, requester: owner, email: "owner@gmail.com")
      expect(result.auto_acceptable?).to be(false)
      expect(result.suggestion.payload["auto_acceptable"]).to be(false)
    end

    it "raises AlreadyClaimedError when the restaurant already has an owner" do
      restaurant.update!(claimed_at: Time.current, claimed_by_user_id: create(:user).id)
      expect {
        described_class.request_claim(restaurant: restaurant, requester: owner, email: "owner@durangosmelter.com")
      }.to raise_error(RestaurantClaim::AlreadyClaimedError)
    end
  end

  describe ".verify" do
    let(:result) { described_class.request_claim(restaurant: restaurant, requester: owner, email: "owner@durangosmelter.com") }
    let(:token)  { result.suggestion.payload["token"] }

    it "marks the restaurant claimed and accepts the Suggestion" do
      described_class.verify(token: token)

      restaurant.reload
      expect(restaurant.claimed_by_user_id).to eq(owner.id)
      expect(restaurant.claimed_at).to be_within(2.seconds).of(Time.current)

      suggestion = Suggestion.last
      expect(suggestion.status).to eq("accepted")
      expect(suggestion.resolved_by_user_id).to eq(owner.id)
      expect(suggestion.resolved_at).to be_present
    end

    it "is idempotent — verifying twice doesn't re-stamp" do
      described_class.verify(token: token)
      restaurant.reload
      first_claimed_at = restaurant.claimed_at

      described_class.verify(token: token)
      restaurant.reload
      expect(restaurant.claimed_at).to eq(first_claimed_at)
    end

    it "raises ExpiredTokenError when the token expired" do
      result.suggestion.update!(
        payload: result.suggestion.payload.merge("expires_at" => 1.day.ago.iso8601)
      )
      expect { described_class.verify(token: token) }.to raise_error(RestaurantClaim::ExpiredTokenError)
    end

    it "raises InvalidTokenError on an unknown token" do
      expect { described_class.verify(token: "no-such-token") }.to raise_error(RestaurantClaim::InvalidTokenError)
    end

    it "raises InvalidTokenError on a blank token" do
      expect { described_class.verify(token: "") }.to raise_error(RestaurantClaim::InvalidTokenError)
    end

    it "raises AlreadyClaimedError when someone else claimed in the meantime" do
      result # generate the token
      restaurant.update!(claimed_at: Time.current, claimed_by_user_id: create(:user).id)
      expect { described_class.verify(token: token) }.to raise_error(RestaurantClaim::AlreadyClaimedError)
    end
  end
end
