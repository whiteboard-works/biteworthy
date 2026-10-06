require "rails_helper"

RSpec.describe "Admin dish photo submissions", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:diner) { create(:user, display_name: "Pat Diner", handle: "pat_diner") }
  let(:restaurant) { create(:restaurant, :published, name: "Nini's") }
  let(:item) { create(:item, :published, restaurant: restaurant, name: "Carne Asada") }
  let(:headers) { auth_headers_for(admin) }
  let!(:submission) { create(:dish_photo_submission, user: diner, item: item) }

  describe "GET /api/v1/admin/photo_submissions" do
    it "defaults to the pending queue with diner, dish, and current photo" do
      get "/api/v1/admin/photo_submissions", headers: headers

      expect(response).to have_http_status(:ok)
      row = response.parsed_body["photo_submissions"].sole
      expect(row).to include("id" => submission.id, "status" => "pending")
      expect(row["user"]).to include("handle" => "pat_diner", "display_name" => "Pat Diner")
      expect(row["item"]).to include("name" => "Carne Asada")
      expect(row["item"]["restaurant"]).to include("name" => "Nini's")
      expect(row["item"]["photo_url"]).to be_nil
      expect(row["photo_url"]).to be_present
    end

    it "404s a non-admin" do
      get "/api/v1/admin/photo_submissions", headers: auth_headers_for(diner)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/admin/photo_submissions/:id/approve" do
    it "sets the diner photo as the dish photo and attributes it" do
      post "/api/v1/admin/photo_submissions/#{submission.id}/approve",
           params: { replace_item_photo: true }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("approved")
      expect(item.reload.photo).to be_attached
      expect(item.photo_submission_id).to eq(submission.id)
    end

    it "can approve without replacing an existing dish photo" do
      item.photo.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
        filename: "staff.jpg",
        content_type: "image/jpeg"
      )
      original = item.photo.blob.id

      post "/api/v1/admin/photo_submissions/#{submission.id}/approve",
           params: { replace_item_photo: false }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(item.reload.photo.blob.id).to eq(original)
      expect(item.photo_submission_id).to be_nil
      expect(response.parsed_body["status"]).to eq("approve_keep")
    end
  end

  describe "POST /api/v1/admin/photo_submissions/:id/reject" do
    it "records the reason and leaves the dish photo alone" do
      post "/api/v1/admin/photo_submissions/#{submission.id}/reject",
           params: { reason: "not_food" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "status" => "rejected",
        "rejection_reason" => "not_food"
      )
      expect(item.reload.photo).not_to be_attached
    end

    it "422s an unknown reason" do
      post "/api/v1/admin/photo_submissions/#{submission.id}/reject",
           params: { reason: "meh" }.to_json,
           headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["allowed"]).to eq(DishPhotoSubmission::REJECTION_REASONS)
    end
  end
end
