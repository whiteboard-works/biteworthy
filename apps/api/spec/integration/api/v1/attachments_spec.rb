require "swagger_helper"

RSpec.describe "attachments", type: :request do
  let(:account) { create(:user) }
  let(:Authorization) do
    token, _ = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/attachments" do
    post("Upload a menu photo or PDF for a scan") do
      description "Returns a signed id the chat and POST /api/v1/scans refer to, so the bytes never " \
                  "enter the agent's context. Authenticate with the session JWT, or with a ticket from " \
                  "POST /api/v1/attachments/ticket in the X-Upload-Ticket header (how the browser uploads, " \
                  "since its JWT lives in an HttpOnly cookie). Files up to the per-file scan limit are " \
                  "stored as sent; a PDF over it, up to 15 MB, is rewritten through Ghostscript first."
      tags "Scans"
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: false
      parameter name: :"X-Upload-Ticket", in: :header, type: :string, required: false,
                description: "A ticket from POST /api/v1/attachments/ticket, in place of Authorization."
      parameter name: :upload, in: :body, required: true, schema: {
        type: :object,
        required: %w[file],
        properties: {
          file: { type: :string, format: :binary, description: "JPEG, PNG, HEIC, WebP, or PDF." }
        }
      }
      parameter name: :file, in: :formData, type: :file, required: true

      response(201, "stored; refer to it by id") do
        schema "$ref" => "#/components/schemas/Attachment"
        let(:file) do
          Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/clean-photo.jpg"), "image/jpeg")
        end
        run_test!
      end

      response(422, "missing, too large, or a type the extractor cannot read") do
        schema "$ref" => "#/components/schemas/Error"
        let(:file) do
          Rack::Test::UploadedFile.new(StringIO.new("#!/bin/sh\n"), "image/jpeg", original_filename: "menu.jpg")
        end
        run_test!
      end

      response(401, "neither a valid bearer token nor a valid ticket") do
        let(:Authorization) { "" }
        let(:file) do
          Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/clean-photo.jpg"), "image/jpeg")
        end
        run_test!
      end
    end
  end

  path "/api/v1/attachments/ticket" do
    post("Mint a short-lived ticket for uploading from a browser") do
      description "The ticket names the caller and expires in minutes; it is good only for " \
                  "POST /api/v1/attachments, sent in the X-Upload-Ticket header."
      tags "Scans"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true

      response(201, "a ticket") do
        schema "$ref" => "#/components/schemas/UploadTicket"
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        run_test!
      end
    end
  end
end
