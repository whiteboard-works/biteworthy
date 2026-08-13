require "swagger_helper"

# The upload door. `Attachment` was already a declared schema and nothing
# pointed at it, so `packages/api-types` carried the shape of a response
# no documented endpoint returned — a type with no path is a type nobody
# can reach from the spec.
#
# What the endpoint is actually for is worth saying in the document
# rather than only in the controller: the id is how bytes stay out of the
# agent's context. The chat sends an id, `start_menu_scan` resolves it to
# a blob, and the vision call happens inside the tool — where text
# injected into a photograph has no tools to reach.
RSpec.describe "attachments", type: :request do
  let(:account) { create(:user, password: "password123") }
  let(:Authorization) do
    token, = Warden::JWTAuth::UserEncoder.new.call(account, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/attachments" do
    post("Upload a menu photo or PDF for scanning") do
      tags "Chat"
      description "Returns a **signed** blob id: unguessable, and recorded against the " \
                  "uploader, so one account cannot scan another's upload by walking ids. " \
                  "The declared content type is not trusted — the real one is sniffed " \
                  "after the write, and a file that is not a JPEG, PNG, HEIC, WebP, or " \
                  "PDF is purged rather than kept."
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      parameter name: :file, in: :formData, required: true,
                schema: { type: :string, format: :binary },
                description: "The image or PDF. Rejected above the size ceiling."

      response(201, "the stored attachment") do
        schema "$ref" => "#/components/schemas/Attachment"
        let(:file) do
          Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/menus/sample.jpg"), "image/jpeg"
          )
        end
        run_test!
      end

      response(422, "nothing attached, too large, or not a scannable type") do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:file) { nil }
        run_test!
      end
    end
  end
end
