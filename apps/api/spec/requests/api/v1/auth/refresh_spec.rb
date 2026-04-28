require "rails_helper"

RSpec.describe "POST /api/v1/auth/refresh", type: :request do
  let!(:user) { create(:user, :confirmed) }

  it "rotates the jti and returns a new JWT" do
    headers = auth_headers_for(user)
    old_jti = user.jti

    post "/api/v1/auth/refresh", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.headers["Authorization"]).to match(/\ABearer .+/)
    expect(user.reload.jti).not_to eq(old_jti)
  end

  it "rejects requests without a valid token" do
    post "/api/v1/auth/refresh"

    expect(response).to have_http_status(:unauthorized)
  end

  it "invalidates the previous token after refresh" do
    headers = auth_headers_for(user)
    post "/api/v1/auth/refresh", headers: headers
    expect(response).to have_http_status(:ok)

    # Old token's jti no longer matches.
    get "/api/v1/profile", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
