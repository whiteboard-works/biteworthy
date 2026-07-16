require "rails_helper"

RSpec.describe "POST /api/v1/auth/login", type: :request do
  let!(:user) { create(:user, :confirmed, password: "password123") }

  it "issues a JWT for valid credentials" do
    post "/api/v1/auth/login",
         params: { user: { email: user.email, password: "password123" } },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.headers["Authorization"]).to match(/\ABearer .+/)
    expect(response.parsed_body["user"]).to include("email" => user.email)
  end

  it "issues a long-lived token so the session outlives a single sitting" do
    # Regression: the token used to expire in 30 minutes while the web
    # session cookie lived 30 days and nothing refreshed it, so any
    # authenticated call after ~30 min 401'd. The token must now last
    # well beyond a single session (matched to the cookie's 30 days).
    post "/api/v1/auth/login",
         params: { user: { email: user.email, password: "password123" } },
         as: :json

    token   = response.headers["Authorization"].sub(/\ABearer /, "")
    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    ttl     = payload["exp"] - Time.now.to_i

    expect(ttl).to be > 1.day.to_i
  end

  it "rejects a wrong password with 401" do
    post "/api/v1/auth/login",
         params: { user: { email: user.email, password: "wrong" } },
         as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Authorization"]).to be_nil
  end

  it "rejects a non-existent email with 401" do
    post "/api/v1/auth/login",
         params: { user: { email: "ghost@example.com", password: "password123" } },
         as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
