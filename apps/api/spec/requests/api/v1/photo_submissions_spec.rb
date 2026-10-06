require "rails_helper"

RSpec.describe "Dish photo submissions API", type: :request do
  let(:user)       { create(:user, display_name: "Pat Diner") }
  let(:other)      { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }
  let(:photo) do
    fixture_file_upload(Rails.root.join("spec/fixtures/files/test-image.jpg"), "image/jpeg")
  end

  describe "POST /api/v1/items/:item_id/photo_submissions" do
    it "creates a pending submission when the diner confirms they took the photo" do
      expect {
        post "/api/v1/items/#{item.id}/photo_submissions",
             params: { photo: photo, owns_rights: true },
             headers: headers
      }.to change(DishPhotoSubmission, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include(
        "status" => "pending",
        "item_id" => item.id,
        "credit_name" => "Pat Diner",
        "owns_rights" => true
      )
      expect(body["photo_url"]).to be_present
      expect(item.reload.photo).not_to be_attached
    end

    it "422s without owns_rights" do
      post "/api/v1/items/#{item.id}/photo_submissions",
           params: { photo: photo, owns_rights: false },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(DishPhotoSubmission.count).to eq(0)
    end

    it "401s anonymously" do
      post "/api/v1/items/#{item.id}/photo_submissions",
           params: { photo: photo, owns_rights: true }

      expect(response).to have_http_status(:unauthorized)
    end

    it "404s on an unpublished dish" do
      draft = create(:item, restaurant: restaurant)
      post "/api/v1/items/#{draft.id}/photo_submissions",
           params: { photo: photo, owns_rights: true },
           headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "429s a fourth pending photo of the same dish" do
      3.times do
        post "/api/v1/items/#{item.id}/photo_submissions",
             params: { photo: photo, owns_rights: true },
             headers: headers
        expect(response).to have_http_status(:created)
      end

      post "/api/v1/items/#{item.id}/photo_submissions",
           params: { photo: photo, owns_rights: true },
           headers: headers

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to eq("pending_limit")
    end
  end

  describe "GET /api/v1/photo_submissions" do
    it "lists only the caller's submissions" do
      mine = create(:dish_photo_submission, user: user, item: item)
      create(:dish_photo_submission, user: other, item: item)

      get "/api/v1/photo_submissions", headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body["photo_submissions"].map { |s| s["id"] }
      expect(ids).to eq([ mine.id ])
    end
  end

  describe "DELETE /api/v1/photo_submissions/:id" do
    it "lets the diner withdraw a pending submission" do
      submission = create(:dish_photo_submission, user: user, item: item)

      delete "/api/v1/photo_submissions/#{submission.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(DishPhotoSubmission.exists?(submission.id)).to be(false)
    end

    it "does not let them delete an approved submission" do
      submission = create(:dish_photo_submission, :approved, user: user, item: item)

      delete "/api/v1/photo_submissions/#{submission.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(DishPhotoSubmission.exists?(submission.id)).to be(true)
    end

    it "404s another diner's submission" do
      submission = create(:dish_photo_submission, user: other, item: item)

      delete "/api/v1/photo_submissions/#{submission.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
