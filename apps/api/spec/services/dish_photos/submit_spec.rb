require "rails_helper"
require "vips"

RSpec.describe DishPhotos::Submit do
  let(:user) { create(:user, display_name: "Pat Diner") }
  let(:item) { create(:item, :published) }

  def jpeg_upload
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/clean-photo.jpg"),
      "image/jpeg"
    )
  end

  it "creates a pending submission with a stripped photo and a credit name" do
    submission = described_class.call(item:, user:, photo: jpeg_upload, owns_rights: true)

    expect(submission).to be_pending
    expect(submission.owns_rights).to be(true)
    expect(submission.credit_name).to eq("Pat Diner")
    expect(submission.photo).to be_attached
    expect(submission.photo.filename.to_s).to match(/\A[0-9a-f-]{36}\.jpg\z/)
  end

  it "refuses when owns_rights is not the strict true/'true'/'1'" do
    expect {
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: "banana")
    }.to raise_error(ActiveRecord::RecordInvalid)
    expect(DishPhotoSubmission.count).to eq(0)
  end

  it "accepts owns_rights as the string 1" do
    expect {
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: "1")
    }.to change(DishPhotoSubmission, :count).by(1)
  end

  it "rate-limits a tenth submission in the same UTC day" do
    restaurant = item.restaurant
    DishPhotoSubmission::DAILY_LIMIT_PER_USER.times do
      described_class.call(
        item: create(:item, :published, restaurant: restaurant),
        user:, photo: jpeg_upload, owns_rights: true
      )
    end

    expect {
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: true)
    }.to raise_error(DishPhotos::Submit::RateLimited, /per day/)
  end

  it "rate-limits a fourth pending photo of the same dish from the same diner" do
    DishPhotoSubmission::PENDING_PER_ITEM_LIMIT.times do
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: true)
    end

    expect {
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: true)
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
      io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename: "review.jpg",
      content_type: "image/jpeg"
    )

    submission = described_class.from_review(review, owns_rights: true)
    expect(submission.review_id).to eq(review.id)
    expect(submission.photo.blob.id).not_to eq(review.photo.blob.id)
  end

  it "still counts a withdrawn upload toward the daily limit" do
    DishPhotoSubmission::DAILY_LIMIT_PER_USER.times do
      row = described_class.call(
        item: create(:item, :published, restaurant: item.restaurant),
        user:, photo: jpeg_upload, owns_rights: true
      )
      row.withdraw!
    end

    expect {
      described_class.call(item:, user:, photo: jpeg_upload, owns_rights: true)
    }.to raise_error(DishPhotos::Submit::RateLimited, /per day/)
  end

  context "when an admin uploads" do
    let(:admin) { create(:user, :admin) }

    def submit_as_admin(owns_rights: true)
      described_class.call(item:, user: admin, photo: jpeg_upload, owns_rights:)
    end

    # An admin is the moderator; queueing their own photo for themselves
    # to approve is busywork that leaves the dish photo-less meanwhile.
    it "approves it straight onto the dish" do
      submission = submit_as_admin

      expect(submission.reload).to be_approved
      expect(submission.reviewed_by).to eq(admin)
      expect(item.reload.photo).to be_attached
      expect(item.photo_submission_id).to eq(submission.id)
    end

    it "replaces an existing dish photo" do
      submit_as_admin
      first_blob_id = item.reload.photo.blob.id

      second = submit_as_admin

      expect(item.reload.photo_submission_id).to eq(second.id)
      expect(item.photo.blob.id).not_to eq(first_blob_id)
    end

    # Seeding a menu's photos is admin work; the daily limit exists to
    # bound moderation load, which an auto-approved upload never adds.
    it "is not held to the diner daily limit" do
      DishPhotoSubmission::DAILY_LIMIT_PER_USER.times { submit_as_admin }

      expect { submit_as_admin }.to change(DishPhotoSubmission, :count).by(1)
    end

    it "still holds the admin to the pending-per-dish limit" do
      allow(DishPhotos::Moderate).to receive(:new).and_raise(ActiveStorage::IntegrityError)
      DishPhotoSubmission::PENDING_PER_ITEM_LIMIT.times { submit_as_admin }

      expect { submit_as_admin }.to raise_error(described_class::RateLimited, /waiting on a moderator/)
    end

    # The row already committed, so a failed approve must not surface as
    # an error the caller retries (a duplicate review, another row). It
    # stays pending in /admin/photos and says so.
    it "returns the submission still pending when the approve fails" do
      allow(DishPhotos::Moderate).to receive(:new).and_raise(ActiveStorage::IntegrityError)

      submission = submit_as_admin

      expect(submission.reload).to be_pending
      expect(item.reload.photo).not_to be_attached
    end

    it "still requires the owns-rights attestation" do
      expect { submit_as_admin(owns_rights: false) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(item.reload.photo).not_to be_attached
    end
  end
end
