require "rails_helper"

RSpec.describe "POST /api/v1/auth/signup", type: :request do
  let(:valid_params) do
    {
      user: {
        email: "new@example.com",
        password: "password123",
        password_confirmation: "password123",
        handle: "new_user",
        display_name: "New User"
      }
    }
  end

  it "creates a user, an empty profile, and returns 201 with a JWT" do
    expect {
      post "/api/v1/auth/signup", params: valid_params, as: :json
    }.to change(User, :count).by(1).and change(UserProfile, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.headers["Authorization"]).to match(/\ABearer .+/)

    body = response.parsed_body
    expect(body["user"]).to include("email" => "new@example.com", "handle" => "new_user")

    user = User.find_by(email: "new@example.com")
    expect(user.profile).to be_present
    expect(user.profile.strictness).to eq("balanced")
  end

  it "rejects a duplicate email with 422" do
    create(:user, email: "taken@example.com")

    post "/api/v1/auth/signup",
         params: valid_params.deep_merge(user: { email: "taken@example.com" }),
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to have_key("email")
  end

  it "rejects an invalid handle with 422" do
    post "/api/v1/auth/signup",
         params: valid_params.deep_merge(user: { handle: "no spaces!" }),
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to have_key("handle")
  end
end
