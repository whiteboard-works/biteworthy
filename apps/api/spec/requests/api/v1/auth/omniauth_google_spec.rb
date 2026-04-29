require "rails_helper"

RSpec.describe "GET /api/v1/auth/google_oauth2/callback", type: :request do
  let(:auth_hash) do
    omniauth_hash(
      provider: :google_oauth2,
      uid: "google-12345",
      email: "newcomer@gmail.com",
      name: "Newcomer Person"
    )
  end

  context "first sign-in" do
    before { mock_omniauth(:google_oauth2, auth_hash) }

    it "creates a User + UserProfile and returns 200 with a JWT" do
      expect {
        get "/api/v1/auth/google_oauth2/callback"
      }.to change(User, :count).by(1).and change(UserProfile, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to match(/\ABearer .+/)

      body = response.parsed_body
      expect(body["user"]).to include(
        "email" => "newcomer@gmail.com",
        "provider" => "google_oauth2"
      )

      user = User.find_by(provider: "google_oauth2", uid: "google-12345")
      expect(user.email).to eq("newcomer@gmail.com")
      expect(user.confirmed_at).to be_present
      expect(user.profile).to be_present
    end
  end

  context "returning user" do
    let!(:existing_user) do
      create(:user, provider: "google_oauth2", uid: "google-12345",
                    email: "newcomer@gmail.com", confirmed_at: Time.current)
    end

    before { mock_omniauth(:google_oauth2, auth_hash) }

    it "matches by [provider, uid] and does not create a duplicate" do
      expect {
        get "/api/v1/auth/google_oauth2/callback"
      }.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Authorization"]).to match(/\ABearer .+/)
      expect(response.parsed_body.dig("user", "id")).to eq(existing_user.id)
    end
  end

  context "OAuth failure (provider rejected the request)" do
    before { mock_omniauth_failure(:google_oauth2, :invalid_credentials) }

    it "returns 401 with a JSON error" do
      get "/api/v1/auth/google_oauth2/callback"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to have_key("error")
    end
  end
end
