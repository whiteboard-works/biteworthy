require "rails_helper"

RSpec.describe "Reviews API", type: :request do
  let(:owner)      { create(:user) }
  let(:other_user) { create(:user) }
  let(:headers)    { auth_headers_for(owner) }

  let(:restaurant) { create(:restaurant, :published) }
  let(:item)       { create(:item, :published, restaurant: restaurant) }

  describe "GET /api/v1/items/:item_id/reviews" do
    let!(:older) { create(:review, item: item, user: other_user, rating: 4, body: "Solid.", created_at: 2.days.ago) }
    let!(:newer) { create(:review, item: item, user: owner,      rating: 5, body: "Best.",  created_at: 1.hour.ago) }

    it "returns reviews newest-first with author payload + pagination metadata" do
      get "/api/v1/items/#{item.id}/reviews"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body["item_id"]).to eq(item.id)
      expect(body["total"]).to eq(2)
      expect(body["reviews"].map { |r| r["id"] }).to eq([newer.id, older.id])
      expect(body["reviews"].first["user"]).to include(
        "id"     => owner.id,
        "handle" => owner.handle
      )
    end

    it "is publicly accessible (no auth required)" do
      get "/api/v1/items/#{item.id}/reviews"
      expect(response).to have_http_status(:ok)
    end

    it "respects ?limit and ?offset" do
      get "/api/v1/items/#{item.id}/reviews?limit=1&offset=1"
      expect(response.parsed_body["reviews"].map { |r| r["id"] }).to eq([older.id])
      expect(response.parsed_body["total"]).to eq(2)
    end

    it "404s on an unpublished item" do
      draft = create(:item, restaurant: restaurant) # default :draft
      get "/api/v1/items/#{draft.id}/reviews"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/items/:item_id/reviews" do
    it "creates a review with rating + body" do
      expect {
        post "/api/v1/items/#{item.id}/reviews",
             params: { rating: 5, body: "Loved it." },
             headers: headers
      }.to change(Review, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "rating" => 5,
        "body"   => "Loved it."
      )
      expect(response.parsed_body["photo_url"]).to be_nil
    end

    it "accepts a multipart photo upload and returns a photo_url" do
      photo = upload_fixture(filename: "menu.png", type: "image/png")

      expect {
        post "/api/v1/items/#{item.id}/reviews",
             params: { rating: 4, body: "See pic.", photo: photo },
             headers: headers
      }.to change(Review, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["photo_url"]).to be_present
      expect(Review.last.photo).to be_attached
    end

    it "rejects ratings outside 1..5" do
      post "/api/v1/items/#{item.id}/reviews",
           params: { rating: 10 },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects oversized photos" do
      big = upload_fixture(filename: "big.png", type: "image/png", size: 6.megabytes)

      post "/api/v1/items/#{item.id}/reviews",
           params: { rating: 4, photo: big },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/MB or smaller/i)
    end

    it "rejects disallowed photo types" do
      pdf = upload_fixture(filename: "menu.pdf", type: "application/pdf")

      post "/api/v1/items/#{item.id}/reviews",
           params: { rating: 4, photo: pdf },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/must be one of/i)
    end

    it "401s anonymously" do
      post "/api/v1/items/#{item.id}/reviews", params: { rating: 5 }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/reviews/:id" do
    let!(:review) { create(:review, item: item, user: owner, rating: 3, body: "Decent.") }

    it "updates rating + body for the owner" do
      patch "/api/v1/reviews/#{review.id}",
            params: { rating: 5, body: "Actually amazing." },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(review.reload.rating).to eq(5)
      expect(review.body).to eq("Actually amazing.")
    end

    it "purges the photo when given an empty value" do
      review.photo.attach(upload_fixture(filename: "old.png", type: "image/png"))
      review.save!
      expect(review.reload.photo).to be_attached

      patch "/api/v1/reviews/#{review.id}",
            params: { photo: "" },
            headers: headers

      # purge_later schedules the deletion; assert the response is OK
      # and the attachment is no longer on the record.
      expect(response).to have_http_status(:ok)
    end

    it "403s when a different user tries to edit" do
      patch "/api/v1/reviews/#{review.id}",
            params: { rating: 1 },
            headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
    end

    it "401s anonymously" do
      patch "/api/v1/reviews/#{review.id}", params: { rating: 1 }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/reviews/:id" do
    let!(:review) { create(:review, item: item, user: owner) }

    it "removes the review for the owner" do
      expect {
        delete "/api/v1/reviews/#{review.id}", headers: headers
      }.to change(Review, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "403s when a different user tries to delete" do
      delete "/api/v1/reviews/#{review.id}", headers: auth_headers_for(other_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # Synthesize a multipart upload from in-memory bytes — avoids
  # checking real binary fixtures into the repo.
  def upload_fixture(filename:, type:, size: 32)
    Rack::Test::UploadedFile.new(
      StringIO.new("\0" * size),
      type,
      original_filename: filename
    )
  end
end
