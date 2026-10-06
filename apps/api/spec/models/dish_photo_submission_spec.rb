require "rails_helper"

RSpec.describe DishPhotoSubmission, type: :model do
  let(:user) { create(:user, display_name: "Pat Diner") }
  let(:item) { create(:item, :published) }

  def attach_photo(submission)
    submission.photo.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/clean-photo.jpg")),
      filename: "dish.jpg",
      content_type: "image/jpeg"
    )
  end

  it "accepts a pending row with a photo and owns_rights" do
    submission = build(:dish_photo_submission, user: user, item: item)
    expect(submission).to be_valid
  end

  it "refuses a submission the diner did not confirm they took" do
    submission = build(:dish_photo_submission, user: user, item: item, owns_rights: false)
    expect(submission).not_to be_valid
    expect(submission.errors[:owns_rights]).to be_present
  end

  it "refuses a row with no photo" do
    submission = DishPhotoSubmission.new(
      user: user, item: item, owns_rights: true, credit_name: "Pat", status: "pending"
    )
    expect(submission).not_to be_valid
    expect(submission.errors[:photo]).to include("must be attached")
  end

  it "requires a rejection reason only when rejected" do
    pending_row = build(:dish_photo_submission, rejection_reason: "low_quality")
    expect(pending_row).not_to be_valid

    rejected = build(:dish_photo_submission, :rejected)
    expect(rejected).to be_valid

    rejected.rejection_reason = nil
    expect(rejected).not_to be_valid
  end

  it "rejects an unknown rejection_reason at the model" do
    submission = build(:dish_photo_submission, :rejected, rejection_reason: "meh")
    expect(submission).not_to be_valid
    expect(submission.errors[:rejection_reason]).to be_present
  end

  it "ties an optional review to the same diner and dish" do
    other = create(:item, :published, restaurant: item.restaurant)
    review = create(:review, user: user, item: other)
    submission = build(:dish_photo_submission, user: user, item: item, review: review)
    expect(submission).not_to be_valid
    expect(submission.errors[:review]).to include("must be of the same dish")
  end

  it "does not overwrite an approved row when withdraw was loaded as pending" do
    submission = create(:dish_photo_submission, user: user, item: item)
    stale = described_class.find(submission.id)
    expect(stale).to be_pending

    DishPhotos::Moderate.new(submission, reviewer: create(:user, :admin))
                        .approve!(replace_item_photo: true)

    expect { stale.withdraw! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(stale.reload).to be_approved
    expect(item.reload.photo).to be_attached
    expect(item.photo.download.bytesize).to be > 32
  end
end
