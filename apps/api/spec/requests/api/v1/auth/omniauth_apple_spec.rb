require "rails_helper"

# Apple Sign-In integration smoke. Live VCR cassettes are deferred
# until the Apple signing key is provisioned in CI (see Phase 1.2 stop
# condition in docs/plans/phase-1.md). For now, the strategy is
# exercised through OmniAuth.test_mode with a mocked auth hash, which
# is enough to verify wiring + the from_omniauth path.
RSpec.describe "GET /api/v1/auth/apple/callback", type: :request do
  let(:auth_hash) do
    omniauth_hash(
      provider: :apple,
      uid: "001234.abcdef.5678",
      email: "appluser@privaterelay.appleid.com",
      name: "Apple User"
    )
  end

  context "first sign-in" do
    before { mock_omniauth(:apple, auth_hash) }

    it "creates a User + UserProfile and returns 200 with a JWT" do
      expect {
        get "/api/v1/auth/apple/callback"
      }.to change(User, :count).by(1).and change(UserProfile, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to match(/\ABearer .+/)

      user = User.find_by(provider: "apple", uid: "001234.abcdef.5678")
      expect(user.email).to eq("appluser@privaterelay.appleid.com")
      expect(user.confirmed_at).to be_present
    end
  end

  context "returning user" do
    let!(:existing_user) do
      create(:user, provider: "apple", uid: "001234.abcdef.5678",
                    email: "appluser@privaterelay.appleid.com",
                    confirmed_at: Time.current)
    end

    before { mock_omniauth(:apple, auth_hash) }

    it "matches by [provider, uid] and does not create a duplicate" do
      expect {
        get "/api/v1/auth/apple/callback"
      }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("user", "id")).to eq(existing_user.id)
    end
  end
end
