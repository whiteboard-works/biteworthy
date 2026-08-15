require "rails_helper"

RSpec.describe "password reset", type: :request do
  let!(:user) { create(:user, :confirmed, password: "original-pass1", password_confirmation: "original-pass1") }

  describe "POST /api/v1/auth/password" do
    it "queues a reset email whose link points at the web app, not the API" do
      post "/api/v1/auth/password", params: { user: { email: user.email } }, as: :json
      expect(response).to have_http_status(:accepted)

      # Async on purpose: a synchronous SMTP call would leak account
      # existence through response latency on this uniform-202 endpoint.
      expect { perform_enqueued_jobs }.to change { ActionMailer::Base.deliveries.count }.by(1)
      mail = ActionMailer::Base.deliveries.last
      body = mail.text_part&.body&.to_s || mail.body.to_s
      expect(body).to include("/reset-password?reset_password_token=")
      expect(body).not_to include("/api/v1/auth/password")
    end

    it "returns the same 202 for an unknown email, sending nothing" do
      # A different answer per email would let anyone probe which
      # addresses have BiteWorthy accounts.
      post "/api/v1/auth/password", params: { user: { email: "ghost@example.com" } }, as: :json
      expect(response).to have_http_status(:accepted)

      perform_enqueued_jobs
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "202s a body with no user key instead of escaping as a raw 400" do
      post "/api/v1/auth/password", params: {}, as: :json
      expect(response).to have_http_status(:accepted)
    end
  end

  describe "PUT /api/v1/auth/password" do
    it "sets the new password and kills every pre-reset session" do
      raw_token = user.send_reset_password_instructions
      old_jti   = user.reload.jti

      put "/api/v1/auth/password",
          params: { user: { reset_password_token: raw_token,
                            password: "new-pass-123", password_confirmation: "new-pass-123" } },
          as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.valid_password?("new-pass-123")).to be(true)
      expect(user.valid_password?("original-pass1")).to be(false)
      # The reset is the remedy for a stolen session — a JWT minted before
      # it must die with the old password (JTIMatcher revocation).
      expect(user.jti).not_to eq(old_jti)
    end

    it "refuses a request that omits password_confirmation entirely" do
      # Devise's confirmation validation is a no-op on nil — without this
      # guard the double-entry check the contract requires is skippable.
      raw_token = user.send_reset_password_instructions

      put "/api/v1/auth/password",
          params: { user: { reset_password_token: raw_token, password: "new-pass-123" } },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to have_key("password_confirmation")
      expect(user.reload.valid_password?("original-pass1")).to be(true)
    end

    it "rejects a bad token with 422 and leaves the password alone" do
      put "/api/v1/auth/password",
          params: { user: { reset_password_token: "bogus",
                            password: "new-pass-123", password_confirmation: "new-pass-123" } },
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      # Field-keyed envelope, same shape as the registrations 422.
      expect(response.parsed_body["errors"]).to be_a(Hash)
      expect(response.parsed_body["errors"]).to have_key("reset_password_token")
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
