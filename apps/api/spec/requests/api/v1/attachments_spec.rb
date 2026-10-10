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
  # The scan limit is 10 MB; a menu exported at print resolution runs
  # past it. The door gives a PDF one Ghostscript pass before refusing.
  describe "a PDF over the scan limit" do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("INGESTION_MAX_INPUT_FILE_BYTES", anything).and_return("200")
    end

    def pdf_upload(bytes)
      body = "%PDF-1.4\n" + ("%" + ("x" * 60) + "\n") * (bytes / 62)
      Rack::Test::UploadedFile.new(StringIO.new(body), "application/pdf", original_filename: "menu.pdf")
    end

    def shrunk_pdf
      file = Tempfile.new([ "shrunk", ".pdf" ], binmode: true)
      file.write("%PDF-1.4\n% small\n")
      file.rewind
      file
    end

    it "stores the shrunk copy when Ghostscript gets it under the limit" do
      allow(Pdfs::Shrink).to receive(:call).and_return(shrunk_pdf)

      post "/api/v1/attachments", params: { file: pdf_upload(1_000) }, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("content_type" => "application/pdf", "filename" => "menu.pdf")
      expect(response.parsed_body["byte_size"]).to be < 100
      expect(Pdfs::Shrink).to have_received(:call).with(a_string_ending_with(".pdf").or(a_kind_of(String)))
    end

    it "refuses it when the shrunk copy is still over the limit" do
      allow(Pdfs::Shrink).to receive(:call).and_return(nil)

      expect { post "/api/v1/attachments", params: { file: pdf_upload(1_000) }, headers: headers }
        .not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("too large")
    end

    # The clients resize photos before sending; a photo still over the
    # limit here is refused as it always was, with no Ghostscript run.
    it "does not try to shrink an image" do
      allow(Pdfs::Shrink).to receive(:call)

      post "/api/v1/attachments", params: { file: upload }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Pdfs::Shrink).not_to have_received(:call)
    end

    it "refuses anything over the raw ceiling without reading it" do
      stub_const("Api::V1::AttachmentsController::MAX_RAW_BYTES", 500)
      allow(Pdfs::Shrink).to receive(:call)

      post "/api/v1/attachments", params: { file: pdf_upload(1_000) }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Pdfs::Shrink).not_to have_received(:call)
    end
  end

  # The browser keeps its session in an HttpOnly cookie it cannot send
  # here, so it uploads with a ticket the proxy minted on its behalf.
  describe "upload tickets" do
    include ActiveSupport::Testing::TimeHelpers

    it "mints a ticket for the signed-in user" do
      post "/api/v1/attachments/ticket", headers: headers

      expect(response).to have_http_status(:created)
      expect(Attachments::UploadTicket.user_for(response.parsed_body["ticket"])).to eq(user)
      expect(Time.iso8601(response.parsed_body["expires_at"])).to be > Time.current
      expect(response.parsed_body["max_bytes"]).to eq(Api::V1::AttachmentsController::MAX_RAW_BYTES)
    end

    # The ceiling never undercuts what the scan would accept, so a larger
    # per-file allowance (the super tier, or the env) reaches the browser.
    it "reports a configured per-file limit above the 15 MB floor as the ceiling" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("INGESTION_MAX_INPUT_FILE_BYTES", anything).and_return((20 * 1024 * 1024).to_s)
      allow(ENV).to receive(:fetch).with("INGESTION_MAX_TOTAL_INPUT_BYTES", anything).and_return((40 * 1024 * 1024).to_s)

      post "/api/v1/attachments/ticket", headers: headers

      expect(response.parsed_body["max_bytes"]).to eq(20 * 1024 * 1024)
    end

    it "requires a session to mint one" do
      post "/api/v1/attachments/ticket"

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts an upload carrying a ticket instead of a JWT" do
      ticket = Attachments::UploadTicket.issue(user)

      post "/api/v1/attachments", params: { file: upload }, headers: { "X-Upload-Ticket" => ticket }

      expect(response).to have_http_status(:created)
      expect(ActiveStorage::Blob.last.metadata["uploaded_by_user_id"]).to eq(user.id)
    end

    it "refuses a forged ticket" do
      post "/api/v1/attachments", params: { file: upload }, headers: { "X-Upload-Ticket" => "not-a-ticket" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an expired ticket" do
      ticket = Attachments::UploadTicket.issue(user)

      travel(Attachments::UploadTicket::TTL + 1.minute) do
        post "/api/v1/attachments", params: { file: upload }, headers: { "X-Upload-Ticket" => ticket }
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it "still refuses an upload with neither credential" do
      post "/api/v1/attachments", params: { file: upload }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
