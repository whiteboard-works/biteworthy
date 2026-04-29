require "rails_helper"

RSpec.describe "DELETE /api/v1/auth/logout", type: :request do
  let!(:user) { create(:user, :confirmed) }

  it "rotates the user's jti and returns 204" do
    expect {
      delete "/api/v1/auth/logout", headers: auth_headers_for(user)
    }.to change { user.reload.jti }

    expect(response).to have_http_status(:no_content)
  end

  it "invalidates the old token for subsequent requests" do
    headers = auth_headers_for(user)
    delete "/api/v1/auth/logout", headers: headers
    expect(response).to have_http_status(:no_content)

    # Old token should no longer authenticate.
    get "/api/v1/profile", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
