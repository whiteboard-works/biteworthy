require "rails_helper"

# Smoke spec — confirms the Rails app boots and the health endpoint
# responds. Real coverage lands alongside the Devise JWT controllers in
# Phase 1.1.
RSpec.describe "boot", type: :request do
  it "responds to the health endpoint" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
