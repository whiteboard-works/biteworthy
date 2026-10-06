require "rails_helper"
require "vips"

RSpec.describe DishPhotos::Submit do
  let(:user) { create(:user, display_name: "Pat Diner") }
  let(:item) { create(:item, :published) }
  let(:photo) do
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/test-image.jpg"),
      "image/jpeg"
    )
  end

  it "creates a pending submission with a stripped photo and a credit name" do
    submission = described_class.call(item:, user:, photo:, owns_rights: true)

    expect(submission).to be_pending
    expect(submission.owns_rights).to be(true)
    expect(submission.credit_name).to eq("Pat Diner")
    expect(submission.photo).to be_attached
  end

  it "refuses when owns_rights is not accepted" do
    expect {
      described_class.call(item:, user:, photo:, owns_rights: false)
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(DishPhotoSubmission.count).to eq(0)
  end

  it "rate-limits a tenth submission in the same UTC day" do
    restaurant = item.restaurant
    DishPhotoSubmission::DAILY_LIMIT_PER_USER.times do
      described_class.call(
        item: create(:item, :published, restaurant: restaurant),
        user:, photo:, owns_rights: true
      )
    end

    expect {
      described_class.call(item:, user:, photo:, owns_rights: true)
    }.to raise_error(DishPhotos::Submit::RateLimited, /per day/)
  end

  it "rate-limits a fourth pending photo of the same dish from the same diner" do
    DishPhotoSubmission::PENDING_PER_ITEM_LIMIT.times do
      described_class.call(item:, user:, photo:, owns_rights: true)
    end

    expect {
      described_class.call(item:, user:, photo:, owns_rights: true)
    }.to raise_error(DishPhotos::Submit::RateLimited, /waiting on a moderator/)
  end

  it "stores the photo without GPS EXIF so a diner upload cannot leak location" do
    gps_file = JpegWithGps.tempfile
    upload = Rack::Test::UploadedFile.new(gps_file.path, "image/jpeg")
    submission = described_class.call(item:, user:, photo: upload, owns_rights: true)
    stored = Vips::Image.new_from_buffer(submission.photo.download, "")
    expect(stored.get_fields.grep(/gps/i)).to be_empty
  ensure
    gps_file&.close!
  end

  it "copies a review photo into its own stripped blob" do
    review = create(:review, user: user, item: item)
    review.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
      filename: "review.jpg",
      content_type: "image/jpeg"
    )

    submission = described_class.from_review(review, owns_rights: true)
    expect(submission.review_id).to eq(review.id)
    expect(submission.photo.blob.id).not_to eq(review.photo.blob.id)
  end
end
