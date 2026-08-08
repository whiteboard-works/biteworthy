require "rails_helper"

RSpec.describe "claim and history tools" do
  let(:user)     { create(:user) }
  let(:stranger) { create(:user) }

  def payload(response) = response.to_h[:structuredContent]

  def call(tool, caller_user, **args)
    tool.call(
      server_context: { user_id: caller_user&.id, public_host: "https://biteworthy.test" },
      **args
    )
  end

  describe Tools::Claims::ClaimRestaurant do
    let(:restaurant) { create(:restaurant, :published, website: "https://ninis.example") }

    it "mails a verification link and claims nothing yet" do
      expect {
        call(described_class, user, restaurant: restaurant.slug, email: "owner@ninis.example")
      }.to have_enqueued_mail(RestaurantClaimMailer, :verify_email)

      expect(restaurant.reload.claimed_by_user_id).to be_nil
      expect(Suggestion.where(kind: "claim").count).to eq(1)
    end

    it "reports whether the address will auto-verify" do
      matched = call(described_class, user, restaurant: restaurant.slug, email: "owner@ninis.example")
      off     = call(described_class, user, restaurant: restaurant.slug, email: "owner@gmail.example")

      expect(payload(matched)[:auto_acceptable]).to be(true)
      expect(payload(off)[:auto_acceptable]).to be(false)
    end

    it "rejects something that is not an email" do
      response = call(described_class, user, restaurant: restaurant.slug, email: "owner")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end

    it "refuses a restaurant somebody already owns" do
      restaurant.update!(claimed_by_user_id: stranger.id, claimed_at: Time.current)

      response = call(described_class, user, restaurant: restaurant.slug, email: "owner@ninis.example")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::Claims::VerifyClaim do
    let(:restaurant) { create(:restaurant, :published, website: "https://ninis.example") }
    let(:claim) do
      RestaurantClaim.request_claim(restaurant: restaurant, requester: user, email: "owner@ninis.example")
    end
    let(:token) { claim.suggestion.payload["token"] }

    it "claims the restaurant for whoever requested it" do
      call(described_class, user, token: token)

      expect(restaurant.reload.claimed_by_user_id).to eq(user.id)
    end

    # Users paste the link out of their inbox far more often than the token.
    it "accepts the whole verification URL" do
      call(described_class, user, token: "https://biteworthy.test/restaurants/#{restaurant.slug}/claim?t=#{token}")

      expect(restaurant.reload.claimed_by_user_id).to eq(user.id)
    end

    it "reports an expired token as recoverable rather than crashing" do
      claim.suggestion.update!(payload: claim.suggestion.payload.merge("expires_at" => 1.day.ago.iso8601))

      response = call(described_class, user, token: token)

      expect(payload(response)[:error]).to eq("invalid_argument")
      expect(restaurant.reload.claimed_by_user_id).to be_nil
    end

    it "rejects a made-up token" do
      response = call(described_class, user, token: "nope")

      expect(payload(response)[:error]).to eq("invalid_argument")
    end
  end

  describe Tools::History::ListVisits do
    let(:restaurant) { create(:restaurant, :published) }
    let!(:visit)     { create(:restaurant_visit, user: user, restaurant: restaurant) }

    it "returns the caller's own visits with the counts they saw" do
      response = call(described_class, user)

      row = payload(response)[:visits].sole
      expect(row[:restaurant][:slug]).to eq(restaurant.slug)
      expect(row[:items_visible_count]).to eq(visit.items_visible_count)
    end

    # Private data. A second account must never see it.
    it "does not leak another user's history" do
      response = call(described_class, stranger)

      expect(payload(response)[:visits]).to be_empty
    end

    it "refuses an anonymous caller" do
      response = call(described_class, nil)

      expect(payload(response)[:error]).to eq("unauthorized")
    end
  end

  describe Tools::History::ListSaved do
    let(:restaurant) { create(:restaurant, :published) }
    let(:item)       { create(:item, :published, restaurant: restaurant) }

    before do
      create(:favorite_restaurant, user: user, restaurant: restaurant)
      create(:favorite_item, user: user, item: item)
    end

    it "returns both kinds by default" do
      response = call(described_class, user)

      expect(payload(response)[:restaurants].sole[:slug]).to eq(restaurant.slug)
      expect(payload(response)[:items].sole[:id]).to eq(item.id)
    end

    it "narrows to one kind on request" do
      response = call(described_class, user, kind: "restaurants")

      expect(payload(response)).to have_key(:restaurants)
      expect(payload(response)).not_to have_key(:items)
    end

    it "fences saved dish names, which came from menus" do
      response = call(described_class, user)

      expect(payload(response)[:items].sole[:name]).to start_with("<untrusted-content>")
    end
  end
end
