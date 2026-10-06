# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/admin/restaurants/:id/backfill_confidence" do
  let(:admin) { create(:user, is_admin: true, password: "password123") }
  let(:user) { create(:user, is_admin: false, password: "password123") }
  let(:restaurant) { create(:restaurant, :published) }

  def headers_for(account)
    { "Authorization" => "Bearer #{jwt_for(account)}" }
  end

  def jwt_for(account)
    Warden::JWTAuth::UserEncoder.new.call(account, :user, nil).first
  end

  it "requires admin access" do
    post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_confidence",
         headers: headers_for(user)
    expect(response).to have_http_status(:not_found)
  end

  it "defaults to dry_run true" do
    post "/api/v1/admin/restaurants/#{restaurant.id}/backfill_confidence",
         headers: headers_for(admin)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["dry_run"]).to be true
    expect(body["restaurant_id"]).to eq(restaurant.id)
    expect(body["items"]).to eq([])
  end
end
