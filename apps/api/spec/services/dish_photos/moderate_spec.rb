require "rails_helper"
require "vips"

RSpec.describe DishPhotos::Moderate do
  let(:admin) { create(:user, :admin) }
  let(:item)  { create(:item, :published) }
  let(:submission) { create(:dish_photo_submission, item: item) }

  def expect_downloadable_photo(attachment)
    expect(attachment).to be_attached
    bytes = attachment.download
    expect(bytes.bytesize).to be > 32
    image = Vips::Image.new_from_buffer(bytes, "")
    expect(image.width).to be > 0
    expect(image.height).to be > 0
  end

  def expect_processed_variants(attachment)
    %i[thumb card full].each do |name|
      bytes = attachment.variant(name).processed.download
      expect(bytes.bytesize).to be > 0
      expect(bytes[0, 4]).to eq("RIFF".b)
    end
  end

  it "copies the diner photo onto a photo-less dish and stores real image bytes" do
    described_class.new(submission, reviewer: admin).approve!(replace_item_photo: true)

    expect(submission.reload).to be_approved
    expect(submission.reviewed_by).to eq(admin)
    expect(item.reload.photo_submission_id).to eq(submission.id)
    expect_downloadable_photo(item.photo)
    expect(item.photo.blob_id).not_to eq(submission.photo.blob_id)
    expect(item.photo.download).to eq(submission.photo.download)
    expect_processed_variants(item.photo)
  end

  it "replaces an existing staff photo only after the diner blob is already stored" do
    item.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename: "staff.jpg",
      content_type: "image/jpeg"
    )
    original_blob_id = item.photo.blob.id
    expect_downloadable_photo(item.photo)

    described_class.new(submission, reviewer: admin).approve!(replace_item_photo: true)

    item.reload
    expect(item.photo.blob.id).not_to eq(original_blob_id)
    expect(item.photo.blob_id).not_to eq(submission.photo.blob_id)
    expect(item.photo_submission_id).to eq(submission.id)
    expect_downloadable_photo(item.photo)
    expect(item.photo.download).to eq(submission.photo.download)
    expect_processed_variants(item.photo)
  end

  it "can approve without replacing an existing dish photo" do
    item.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename: "staff.jpg",
      content_type: "image/jpeg"
    )
    original_blob = item.photo.blob.id

    described_class.new(submission, reviewer: admin).approve!(replace_item_photo: false)

    expect(submission.reload).to be_approve_keep
    expect(item.reload.photo.blob.id).to eq(original_blob)
    expect(item.photo_submission_id).to be_nil
    expect_downloadable_photo(item.photo)
  end

  it "purges the stored image on reject so the old link stops working" do
    described_class.new(submission, reviewer: admin).reject!(reason: "not_this_dish")

    expect(submission.reload).to be_rejected
    expect(submission.photo).not_to be_attached
    expect(submission.rejection_reason).to eq("not_this_dish")
    expect(item.reload.photo).not_to be_attached
  end

  it "refuses a second decision on an already-moderated row" do
    described_class.new(submission, reviewer: admin).reject!(reason: "low_quality")

    expect {
      described_class.new(submission, reviewer: admin).approve!(replace_item_photo: true)
    }.to raise_error(DishPhotos::Moderate::NotPending)
  end

  it "refuses an unknown rejection reason" do
    expect {
      described_class.new(submission, reviewer: admin).reject!(reason: "meh")
    }.to raise_error(DishPhotos::Moderate::InvalidReason)
  end
end
