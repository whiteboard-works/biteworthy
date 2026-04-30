require "rails_helper"

RSpec.describe "Restaurant claim flow", type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published, name: "Durango Smelter Pub", website: "https://durangosmelter.com") }

  describe "POST /api/v1/restaurants/:id/claim" do
    it "creates a Suggestion + enqueues the verify-email mailer" do
      expect {
        expect {
          post "/api/v1/restaurants/#{restaurant.id}/claim",
               params: { email: "owner@durangosmelter.com" },
               headers: headers
        }.to change(Suggestion, :count).by(1)
      }.to have_enqueued_mail(RestaurantClaimMailer, :verify_email)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include(
        "status" => "verification_sent",
        "auto_acceptable" => true
      )
    end

    it "marks auto_acceptable: false on a domain mismatch but still mails" do
      post "/api/v1/restaurants/#{restaurant.id}/claim",
           params: { email: "owner@gmail.com" },
           headers: headers
      expect(response.parsed_body["auto_acceptable"]).to be(false)
    end

    it "401s anonymously" do
      post "/api/v1/restaurants/#{restaurant.id}/claim", params: { email: "x@y.com" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "422s on a missing email" do
      post "/api/v1/restaurants/#{restaurant.id}/claim", params: { email: "" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "409s when the restaurant is already claimed" do
      restaurant.update!(claimed_at: Time.current, claimed_by_user_id: create(:user).id)
      post "/api/v1/restaurants/#{restaurant.id}/claim",
           params: { email: "owner@durangosmelter.com" },
           headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "looks up the restaurant by slug too" do
      post "/api/v1/restaurants/#{restaurant.slug}/claim",
           params: { email: "owner@durangosmelter.com" },
           headers: headers
      expect(response).to have_http_status(:accepted)
    end
  end

  describe "GET /api/v1/restaurants/:id/claim/verify" do
    let!(:result) do
      RestaurantClaim.request_claim(restaurant: restaurant, requester: user, email: "owner@durangosmelter.com")
    end
    let(:token) { result.suggestion.payload["token"] }

    it "marks the restaurant claimed and returns the new state, anonymously" do
      get "/api/v1/restaurants/#{restaurant.id}/claim/verify?t=#{token}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("claimed")
      expect(body["restaurant"]).to include(
        "claimed_by_user_id" => user.id
      )
    end

    it "422s on an unknown token" do
      get "/api/v1/restaurants/#{restaurant.id}/claim/verify?t=bogus"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["kind"]).to eq("InvalidTokenError")
    end

    it "422s on an expired token" do
      Suggestion.last.update!(payload: result.suggestion.payload.merge("expires_at" => 1.day.ago.iso8601))
      get "/api/v1/restaurants/#{restaurant.id}/claim/verify?t=#{token}"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["kind"]).to eq("ExpiredTokenError")
    end
  end
end
