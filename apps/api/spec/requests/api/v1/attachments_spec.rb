require "rails_helper"

# Uploads exist so menu photos reach the extractor without their bytes
# ever entering the agent's context — the chat only ever handles an id.
RSpec.describe "Api::V1::Attachments", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def upload(path: Rails.root.join("spec/fixtures/menus/sample.jpg"), type: "image/jpeg")
    fixture_file_upload(path, type)
  end

  it "stores the file and returns an id the scan tool can resolve" do
    post "/api/v1/attachments", params: { file: upload }, headers: headers

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("content_type" => "image/jpeg", "filename" => "sample.jpg")
    expect(response.parsed_body["byte_size"]).to be > 0
  end

  # Blob primary keys are sequential integers. A raw id would let any
  # account attach any other account's upload by counting upwards.
  it "returns a signed id, not the primary key" do
    post "/api/v1/attachments", params: { file: upload }, headers: headers

    id = response.parsed_body["id"]
    expect(id).not_to eq(ActiveStorage::Blob.last.id.to_s)
    expect(ActiveStorage::Blob.find_signed(id)).to eq(ActiveStorage::Blob.last)
  end

  it "records who uploaded it" do
    post "/api/v1/attachments", params: { file: upload }, headers: headers

    expect(ActiveStorage::Blob.last.metadata["uploaded_by_user_id"]).to eq(user.id)
  end

  # The declared content type is whatever the client felt like sending;
  # ActiveStorage sniffs the real one, so the check that counts is after
  # the write.
  it "refuses a file type the extractor cannot read" do
    file = Rack::Test::UploadedFile.new(StringIO.new("#!/bin/sh\necho hi\n"), "image/jpeg",
                                        original_filename: "menu.jpg")

    expect { post "/api/v1/attachments", params: { file: file }, headers: headers }
      .not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "refuses a file over the scan size limit" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("INGESTION_MAX_INPUT_FILE_BYTES", anything).and_return("10")

    post "/api/v1/attachments", params: { file: upload }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("too large")
  end

  it "requires a file" do
    post "/api/v1/attachments", params: {}, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires a signed-in caller" do
    post "/api/v1/attachments", params: { file: upload }

    expect(response).to have_http_status(:unauthorized)
  end

  describe "handing the id to start_menu_scan" do
    let!(:city)       { create(:city, slug: "durango", name: "Durango") }
    let!(:restaurant) { create(:restaurant, :published, city: city, slug: "ninis") }

    def scan_with(id, as:)
      Tools::Ingestion::StartMenuScan.call(
        server_context: { user_id: as.id },
        restaurant: "ninis", attachment_ids: [id]
      ).to_h
    end

    def upload_as(account)
      post "/api/v1/attachments", params: { file: upload }, headers: auth_headers_for(account)
      response.parsed_body["id"]
    end

    it "starts a scan from the uploader's own attachment" do
      allow(ExtractMenuJob).to receive(:perform_later)

      expect(scan_with(upload_as(user), as: user)[:structuredContent]).to include(status: "extracting")
    end

    # The signature makes the id unguessable; the recorded uploader is
    # what actually stops a shared or leaked id from being replayed.
    it "ignores an attachment uploaded by someone else" do
      stranger_id = upload_as(create(:user))

      result = scan_with(stranger_id, as: user)

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include("Provide one of")
    end
  end
end
