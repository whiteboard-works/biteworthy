require "rails_helper"

RSpec.describe DishPhotos::Moderate do
  let(:admin) { create(:user, :admin) }
  let(:item)  { create(:item, :published) }
  let(:submission) { create(:dish_photo_submission, item: item) }

  it "copies the diner photo onto the dish through ItemEditor so variants exist" do
    described_class.new(submission, reviewer: admin).approve!(replace_item_photo: true)

    expect(submission.reload).to be_approved
    expect(submission.reviewed_by).to eq(admin)
    expect(item.reload.photo).to be_attached
    expect(item.photo_submission_id).to eq(submission.id)
    expect(item.photo.variant(:card)).to be_present
  end

  it "can approve without replacing an existing dish photo" do
    item.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/test-image.jpg")),
      filename: "staff.jpg",
      content_type: "image/jpeg"
    )
    original_blob = item.photo.blob.id

    described_class.new(submission, reviewer: admin).approve!(replace_item_photo: false)

    expect(submission.reload).to be_approved
    expect(item.reload.photo.blob.id).to eq(original_blob)
    expect(item.photo_submission_id).to be_nil
  end

  it "records a rejection reason" do
    described_class.new(submission, reviewer: admin).reject!(reason: "not_this_dish")

    expect(submission.reload).to be_rejected
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
