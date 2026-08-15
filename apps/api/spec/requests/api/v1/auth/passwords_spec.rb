require "rails_helper"

RSpec.describe "password reset", type: :request do
  let!(:user) { create(:user, :confirmed, password: "original-pass1", password_confirmation: "original-pass1") }

  describe "POST /api/v1/auth/password" do
    it "emails a reset link that points at the web app, not the API" do
      expect {
        post "/api/v1/auth/password", params: { user: { email: user.email } }, as: :json
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(response).to have_http_status(:accepted)
      body = ActionMailer::Base.deliveries.last.text_part&.body&.to_s ||
             ActionMailer::Base.deliveries.last.body.to_s
      expect(body).to include("/reset-password?reset_password_token=")
      expect(body).not_to include("/api/v1/auth/password")
    end

    it "returns the same 202 for an unknown email, sending nothing" do
      # A different answer per email would let anyone probe which
      # addresses have BiteWorthy accounts.
      expect {
        post "/api/v1/auth/password", params: { user: { email: "ghost@example.com" } }, as: :json
      }.not_to change { ActionMailer::Base.deliveries.count }

      expect(response).to have_http_status(:accepted)
    end
  end

  describe "PUT /api/v1/auth/password" do
    it "sets the new password when the token is valid" do
      raw_token = user.send_reset_password_instructions

      put "/api/v1/auth/password",
          params: { user: { reset_password_token: raw_token,
                            password: "new-pass-123", password_confirmation: "new-pass-123" } },
          as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.valid_password?("new-pass-123")).to be(true)
      expect(user.valid_password?("original-pass1")).to be(false)
    end

    it "rejects a bad token with 422 and leaves the password alone" do
      put "/api/v1/auth/password",
          params: { user: { reset_password_token: "bogus",
                            password: "new-pass-123", password_confirmation: "new-pass-123" } },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
      expect(user.reload.valid_password?("original-pass1")).to be(true)
    end

    it "rejects a mismatched confirmation with 422" do
      raw_token = user.send_reset_password_instructions

      put "/api/v1/auth/password",
          params: { user: { reset_password_token: raw_token,
                            password: "new-pass-123", password_confirmation: "different" } },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.valid_password?("original-pass1")).to be(true)
    end
  end
end
