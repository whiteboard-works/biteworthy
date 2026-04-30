require "rails_helper"

RSpec.describe "POST /api/v1/waitlist_signups", type: :request do
  let(:url) { "/api/v1/waitlist_signups" }

  before { ActionMailer::Base.deliveries.clear }

  it "creates the signup + fires the confirmation mailer (anonymous)" do
    expect {
      post url, params: { waitlist_signup: { email: "skylar@example.com" } }, as: :json
    }.to change(WaitlistSignup, :count).by(1)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["ok"]).to be true
    expect(body["duplicate"]).to be false

    perform_enqueued_jobs
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["skylar@example.com"])
    expect(ActionMailer::Base.deliveries.last.subject).to eq("You're on the BiteWorthy waitlist")
  end

  it "is idempotent on a duplicate email — 200 + duplicate=true, no second mail" do
    WaitlistSignup.create!(email: "skylar@example.com")
    expect {
      post url, params: { waitlist_signup: { email: "Skylar@Example.com" } }, as: :json
    }.not_to change(WaitlistSignup, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["duplicate"]).to be true
    perform_enqueued_jobs
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "422s on a malformed email" do
    post url, params: { waitlist_signup: { email: "not-an-email" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to be_present
  end

  it "honors the optional source param" do
    post url, params: { waitlist_signup: { email: "press@example.com", source: "press" } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(WaitlistSignup.find_by(email: "press@example.com").source).to eq("press")
  end

  it "rejects an unknown source value" do
    post url, params: { waitlist_signup: { email: "ok@example.com", source: "twitter_dm" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
