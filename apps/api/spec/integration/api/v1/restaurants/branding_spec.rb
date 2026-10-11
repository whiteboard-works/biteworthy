require "swagger_helper"

RSpec.describe "restaurants/branding", type: :request do
  def bearer_for(user)
    token, _ = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    "Bearer #{token}"
  end

  path "/api/v1/restaurants/{restaurant_id}/branding" do
    parameter name: :restaurant_id, in: :path, type: :string,
              description: "Restaurant id or slug"

    patch("Set the restaurant's logo and banner") do
      tags "Restaurants"
      description "The verified owner (claimed_by_user_id), an admin, or, while the restaurant " \
                  "is still a draft, the person who added it. Each image is " \
                  "re-encoded without EXIF/GPS and cropped to its slot (logo 1:1 up to 400×400, " \
                  "banner 8:3 up to 1600×600; center unless `*_crop` says otherwise, never " \
                  "enlarged); a new one replaces the old. Omitted fields " \
                  "leave that image alone; `remove_logo` / `remove_banner` clear one. " \
                  "Answers with the same row as GET /restaurants/{id}."
      consumes "multipart/form-data"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :Authorization, in: :header, type: :string, required: true
      # Object schema first so OAS3 requestBody keeps every field; formData
      # lets still drive run_test.
      parameter name: :branding, in: :body, required: false, schema: {
        type: :object,
        properties: {
          logo:          { type: :string, format: :binary, description: "JPEG, PNG, WebP, or HEIC." },
          banner:        { type: :string, format: :binary, description: "JPEG, PNG, WebP, or HEIC." },
          remove_logo:   { type: :boolean },
          remove_banner: { type: :boolean },
          logo_crop:     { "$ref" => "#/components/schemas/BrandingCrop" },
          banner_crop:   { "$ref" => "#/components/schemas/BrandingCrop" }
        }
      }
      parameter name: :logo, in: :formData, type: :file, required: false
      parameter name: :banner, in: :formData, type: :file, required: false
      parameter name: :remove_logo, in: :formData, type: :boolean, required: false
      parameter name: :remove_banner, in: :formData, type: :boolean, required: false

      let(:owner) { create(:user) }
      let(:restaurant) { create(:restaurant, :published, claimed_by_user: owner, claimed_at: Time.current) }
      let(:restaurant_id) { restaurant.slug }
      let(:logo) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/clean-photo.jpg"), "image/jpeg") }
      let(:banner) { nil }
      let(:remove_logo) { nil }
      let(:remove_banner) { nil }

      response(200, "the restaurant, with its new image URLs") do
        schema "$ref" => "#/components/schemas/RestaurantDetail"
        let(:Authorization) { bearer_for(owner) }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["logo_url"]).to be_present
          expect(body["banner_url"]).to be_nil
        end
      end

      response(403, "signed in, but not the owner, an admin, or the creator of this draft") do
        schema "$ref" => "#/components/schemas/Error"
        let(:Authorization) { bearer_for(create(:user)) }
        run_test!
      end

      response(422, "not an image, too large, or a bad crop") do
        schema type: :object,
               required: %w[error],
               properties: { error: { type: :string }, code: { type: :string } }
        let(:Authorization) { bearer_for(owner) }
        let(:logo) do
          Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "menu.pdf")
        end
        run_test!
      end

      response(401, "missing or invalid bearer token") do
        let(:Authorization) { "" }
        let(:logo) { nil }
        run_test!
      end
    end
  end
end
