require "rails_helper"

RSpec.describe "POST /api/v1/dmca_notices (legal E10)", type: :request do
  let(:url) { "/api/v1/dmca_notices" }

  let(:valid) do
    {
      dmca_notice: {
        complainant_name:  "Ansel Adams Estate",
        complainant_email: "Legal@Example.com",
        infringing_url:    "https://bite-worthy.com/restaurants/foo/items/bar",
        work_description:  "My copyrighted dish photograph, used without a license.",
        good_faith:        true,
        accuracy_sworn:    true,
        signature:         "Jane Counsel"
      }
    }
  end

  it "stores a valid takedown notice anonymously and normalizes the email" do
    expect {
      post url, params: valid, as: :json
    }.to change(DmcaNotice, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["ok"]).to be true

    notice = DmcaNotice.last
    expect(notice.status).to eq("received")
    expect(notice.complainant_email).to eq("legal@example.com")
  end

  it "422s when a sworn statement is not affirmed" do
    post url, params: valid.deep_merge(dmca_notice: { good_faith: false }), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"].join).to match(/affirmed/i)
  end

  it "422s on a malformed complainant email" do
    post url, params: valid.deep_merge(dmca_notice: { complainant_email: "nope" }), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "422s when the work description is missing" do
    post url, params: valid.deep_merge(dmca_notice: { work_description: "" }), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
